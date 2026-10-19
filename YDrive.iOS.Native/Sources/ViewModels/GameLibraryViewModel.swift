import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class GameLibraryViewModel: ObservableObject {
    @Published var games: [GameItem] = []
    @Published var searchText: String = ""
    @Published var isFilePickerPresented: Bool = false
    
    private let saveKey = "YDrive_SavedGames"
    
    init() {
        loadLibrary()
    }
    
    private func saveLibrary() {
        if let encoded = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadLibrary() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([GameItem].self, from: data) {
            var updated = false
            self.games = decoded.map { game in
                var g = game
                // If console was previously defaulted to SEGA Genesis, re-evaluate if it's actually 32X, Master System, etc.
                if g.consoleName == "SEGA Genesis" {
                    let fileURL = URL(fileURLWithPath: g.fileName)
                    let detected = Self.detectConsole(url: fileURL, title: g.title)
                    if detected != g.consoleName {
                        g.consoleName = detected
                        updated = true
                    }
                }
                return g
            }
            if updated {
                saveLibrary()
            }
        }
    }

    var filteredGames: [GameItem] {
        if searchText.isEmpty { return games }
        return games.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    func addRom(url: URL) {
        // Security-scoped resource access is required for file-picker URLs.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Copy the ROM into the app's Documents directory so the path remains
        // valid after the security scope ends and across app relaunches.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = docs.appendingPathComponent(url.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            print("[ViewModel] ROM copy failed: \(error)")
        }

        let name = url.deletingPathExtension().lastPathComponent
        let console = Self.detectConsole(url: dest, title: name)
        
        let item = GameItem(
            title: name,
            consoleName: console,
            fileName: dest.path   // store the full absolute path
        )
        games.append(item)
        saveLibrary()

        Task {
            await fetchMetadata(for: item.id)
        }
    }

    func deleteGame(_ game: GameItem) {
        games.removeAll { $0.id == game.id }
        saveLibrary()
    }

    func renameGame(_ game: GameItem, to newName: String) {
        if let index = games.firstIndex(of: game) {
            games[index].title = newName
            saveLibrary()
        }
    }

    func removeCoverImage(for game: GameItem) {
        guard let index = games.firstIndex(of: game) else { return }
        if let path = games[index].coverImagePath {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let file = docs.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
            try? FileManager.default.removeItem(at: file)
        }
        games[index].coverImagePath = nil
        saveLibrary()
    }

    func updateCoverImageData(for game: GameItem, imageData: Data) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imgName = UUID().uuidString + ".jpg"
        let imgDest = docs.appendingPathComponent(imgName)
        
        do {
            try imageData.write(to: imgDest)
            if let index = games.firstIndex(of: game) {
                // If there's an existing custom cover, we could remove it, but for simplicity just overwrite the path.
                games[index].coverImagePath = imgDest.path
                saveLibrary()
            }
        } catch {
            print("[ViewModel] Failed to save custom cover image: \(error)")
        }
    }

    func fetchMetadata(for gameId: UUID) async {
        guard let game = games.first(where: { $0.id == gameId }) else { return }
        
        if let result = await TheGamesDBClient.shared.fetchMetadata(for: game.title, consoleName: game.consoleName, fileName: game.fileName) {
            if let index = self.games.firstIndex(where: { $0.id == gameId }) {
                if let dev = result.developer { self.games[index].developer = dev }
                if let year = result.releaseYear { self.games[index].releaseYear = year }
                if let sum = result.summary { self.games[index].summary = sum }
                self.saveLibrary()
            }
            
            if let imgUrlString = result.coverImageUrl, let imgUrl = URL(string: imgUrlString) {
                if let (data, _) = try? await URLSession.shared.data(from: imgUrl) {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let imgName = UUID().uuidString + ".jpg"
                    let imgDest = docs.appendingPathComponent(imgName)
                    try? data.write(to: imgDest)
                    if let index = self.games.firstIndex(where: { $0.id == gameId }) {
                        self.games[index].coverImagePath = imgDest.path
                        self.saveLibrary()
                    }
                }
            }
        }
    }

    // ── Console Detection ─────────────────────────────────────────────────────
    static func detectConsole(url: URL, title: String? = nil) -> String {
        let ext = url.pathExtension.lowercased()
        let filename = url.lastPathComponent.lowercased()
        let gameTitle = (title ?? url.deletingPathExtension().lastPathComponent).lowercased()

        // 1. Direct extension match
        switch ext {
        case "32x":
            return "SEGA 32X"
        case "sms":
            return "SEGA Master System"
        case "gg":
            return "SEGA Game Gear"
        case "chd", "iso", "cue":
            return "SEGA CD"
        case "md", "gen", "smd":
            if check32XHeader(at: url) {
                return "SEGA 32X"
            }
            return "SEGA Genesis"
        default:
            break
        }

        // 2. Binary header inspection (for .bin, .rom, or unknown extensions)
        if FileManager.default.fileExists(atPath: url.path) {
            if check32XHeader(at: url) {
                return "SEGA 32X"
            }
            if checkMasterSystemHeader(at: url) {
                return "SEGA Master System"
            }
            if checkGenesisHeader(at: url) {
                return "SEGA Genesis"
            }
        }

        // 3. Filename / Title pattern heuristics
        let searchString = "\(filename) \(gameTitle)"
        
        // 32X hints
        if searchString.contains("(32x)") || searchString.contains("[32x]") || searchString.contains(" 32x") || searchString.contains("-32x") {
            return "SEGA 32X"
        }
        
        // Master System hints
        if searchString.contains("(sms)") || searchString.contains("[sms]") || searchString.contains("master system") || searchString.contains("(ms)") {
            return "SEGA Master System"
        }
        
        // Game Gear hints
        if searchString.contains("(gg)") || searchString.contains("[gg]") || searchString.contains("game gear") {
            return "SEGA Game Gear"
        }
        
        // Sega CD hints
        if searchString.contains("(sega cd)") || searchString.contains("[sega cd]") || searchString.contains("mega-cd") || searchString.contains("sega cd") || searchString.contains("(scd)") {
            return "SEGA CD"
        }

        // Default
        return "SEGA Genesis"
    }

    private static func check32XHeader(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        
        guard let data = try? handle.read(upToCount: 512), data.count >= 0x120 else { return false }
        let slice = data[0x100..<0x120]
        if let str = String(data: slice, encoding: .ascii) {
            if str.contains("32X") {
                return true
            }
        }
        return false
    }

    private static func checkMasterSystemHeader(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        
        guard let data = try? handle.read(upToCount: 0xC000), data.count >= 0x2000 else { return false }
        guard let tmrSega = "TMR SEGA".data(using: .ascii) else { return false }
        
        let standardOffsets = [0x7FF0, 0x3FF0, 0x1FF0, 0xBFF0]
        for offset in standardOffsets {
            if data.count >= offset + 8 {
                let slice = data[offset..<(offset + 8)]
                if slice == tmrSega {
                    return true
                }
            }
        }
        
        let shiftedOffsets = [0x81F0, 0x41F0, 0x21F0]
        for offset in shiftedOffsets {
            if data.count >= offset + 8 {
                let slice = data[offset..<(offset + 8)]
                if slice == tmrSega {
                    return true
                }
            }
        }
        
        return false
    }

    private static func checkGenesisHeader(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        
        guard let data = try? handle.read(upToCount: 512), data.count >= 0x110 else { return false }
        let slice = data[0x100..<0x110]
        if let str = String(data: slice, encoding: .ascii) {
            if str.hasPrefix("SEGA") {
                return true
            }
        }
        return false
    }
}
