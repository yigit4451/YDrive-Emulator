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
        Self.ensureDirectoryStructure()
        loadLibrary()
        syncWithDocumentsDirectory()
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

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var romsDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("ROM's", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var biosDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("BIOS", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func ensureDirectoryStructure() {
        _ = romsDirectory
        _ = biosDirectory
    }

    func addRom(url: URL) {
        // Security-scoped resource access is required for file-picker URLs.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let name = url.deletingPathExtension().lastPathComponent
        let romsDir = Self.romsDirectory
        let gameFolder = romsDir.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)

        let dest = gameFolder.appendingPathComponent(url.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            print("[ViewModel] ROM copy failed: \(error)")
        }

        let console = Self.detectConsole(url: dest, title: name)

        var existingCover: String? = nil
        for coverName in ["cover.jpg", "cover.png", "\(name).jpg", "\(name).png"] {
            let candidate = gameFolder.appendingPathComponent(coverName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                existingCover = candidate.path
                break
            }
        }

        let item = GameItem(
            title: name,
            consoleName: console,
            fileName: dest.path,
            coverImagePath: existingCover
        )
        games.append(item)
        saveLibrary()

        if existingCover == nil {
            Task {
                await fetchMetadata(for: item.id)
            }
        }
    }

    func deleteGame(_ game: GameItem) {
        games.removeAll { $0.id == game.id }
        let fileURL = URL(fileURLWithPath: game.fileName)
        let gameFolder = fileURL.deletingLastPathComponent()

        // If game is in its own subfolder inside ROM's, delete the entire folder
        if gameFolder.lastPathComponent != "ROM's" && gameFolder.path.contains("ROM's") {
            try? FileManager.default.removeItem(at: gameFolder)
        } else {
            if FileManager.default.fileExists(atPath: game.fileName) {
                try? FileManager.default.removeItem(atPath: game.fileName)
            }
            if let cover = game.coverImagePath, FileManager.default.fileExists(atPath: cover) {
                try? FileManager.default.removeItem(atPath: cover)
            }
        }
        saveLibrary()
    }

    /// Scans the app's Documents directory (exposed in the Files app) for any ROM files added manually.
    func syncWithDocumentsDirectory() {
        let docs = Self.documentsDirectory
        let romsDir = Self.romsDirectory
        let biosDir = Self.biosDirectory
        let fm = FileManager.default

        let supportedExtensions = Set(["md", "bin", "gen", "smd", "zip", "chd", "32x", "sms", "gg", "iso", "cue"])
        let biosNames = Set(["bios_cd_u.bin", "bios_cd_j.bin", "bios_cd_e.bin"])

        var updated = false

        // ── 1. Migration of BIOS files from root to BIOS/ ──
        if let rootFiles = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for file in rootFiles {
                let lowerName = file.lastPathComponent.lowercased()
                if biosNames.contains(lowerName) {
                    let dest = biosDir.appendingPathComponent(file.lastPathComponent)
                    if !fm.fileExists(atPath: dest.path) {
                        try? fm.moveItem(at: file, to: dest)
                    } else {
                        try? fm.removeItem(at: file)
                    }
                }
            }
        }

        // ── 2. Migration of loose ROM files from root to ROM's/<Game>/ ──
        if let rootFiles = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for file in rootFiles {
                let ext = file.pathExtension.lowercased()
                let lowerName = file.lastPathComponent.lowercased()
                guard supportedExtensions.contains(ext), !biosNames.contains(lowerName) else { continue }

                let gameTitle = file.deletingPathExtension().lastPathComponent
                let gameFolder = romsDir.appendingPathComponent(gameTitle, isDirectory: true)
                try? fm.createDirectory(at: gameFolder, withIntermediateDirectories: true)
                let dest = gameFolder.appendingPathComponent(file.lastPathComponent)

                if !fm.fileExists(atPath: dest.path) {
                    try? fm.moveItem(at: file, to: dest)
                }

                if let idx = games.firstIndex(where: { $0.fileName == file.path }) {
                    games[idx].fileName = dest.path
                    updated = true
                }
            }
        }

        // ── 3. Migration of loose ROM files directly in ROM's/ (not in subfolders) ──
        if let romsRootFiles = try? fm.contentsOfDirectory(at: romsDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for file in romsRootFiles {
                guard let vals = try? file.resourceValues(forKeys: [.isRegularFileKey]), vals.isRegularFile == true else { continue }
                let ext = file.pathExtension.lowercased()
                let lowerName = file.lastPathComponent.lowercased()
                guard supportedExtensions.contains(ext), !biosNames.contains(lowerName) else { continue }

                let gameTitle = file.deletingPathExtension().lastPathComponent
                let gameFolder = romsDir.appendingPathComponent(gameTitle, isDirectory: true)
                try? fm.createDirectory(at: gameFolder, withIntermediateDirectories: true)
                let dest = gameFolder.appendingPathComponent(file.lastPathComponent)

                if !fm.fileExists(atPath: dest.path) {
                    try? fm.moveItem(at: file, to: dest)
                }

                if let idx = games.firstIndex(where: { $0.fileName == file.path }) {
                    games[idx].fileName = dest.path
                    updated = true
                }
            }
        }

        // ── 4. Migration of old Saves/ folder to corresponding game folders ──
        let legacySavesDir = docs.appendingPathComponent("Saves", isDirectory: true)
        if fm.fileExists(atPath: legacySavesDir.path),
           let saveFiles = try? fm.contentsOfDirectory(at: legacySavesDir, includingPropertiesForKeys: nil) {
            for saveFile in saveFiles {
                let saveName = saveFile.lastPathComponent
                for game in games {
                    let safeName = game.fileName.replacingOccurrences(of: "/", with: "_")
                    let safeTitle = game.title
                    if saveName.hasPrefix("\(safeName)_slot") || saveName.hasPrefix("\(safeTitle)_slot") {
                        let gameFolder = URL(fileURLWithPath: game.fileName).deletingLastPathComponent()
                        let slotPart = saveName.components(separatedBy: "_slot").last ?? "0.state"
                        let dest = gameFolder.appendingPathComponent("slot\(slotPart)")
                        if !fm.fileExists(atPath: dest.path) {
                            try? fm.moveItem(at: saveFile, to: dest)
                        } else {
                            try? fm.removeItem(at: saveFile)
                        }
                    }
                }
            }
            if let remaining = try? fm.contentsOfDirectory(atPath: legacySavesDir.path), remaining.isEmpty {
                try? fm.removeItem(at: legacySavesDir)
            }
        }

        // ── 5. Discover all games in ROM's/ subfolders ──
        var currentGames: [GameItem] = []
        for var game in games {
            if fm.fileExists(atPath: game.fileName) {
                currentGames.append(game)
            } else {
                let romName = (game.fileName as NSString).lastPathComponent
                var found = false
                if let subfolders = try? fm.contentsOfDirectory(at: romsDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    for folder in subfolders {
                        let candidate = folder.appendingPathComponent(romName)
                        if fm.fileExists(atPath: candidate.path) {
                            game.fileName = candidate.path
                            currentGames.append(game)
                            found = true
                            updated = true
                            break
                        }
                    }
                }
                if !found {
                    updated = true
                }
            }
        }

        var existingPaths = Set(currentGames.map { $0.fileName })

        guard let enumerator = fm.enumerator(
            at: romsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            if updated {
                self.games = currentGames
                saveLibrary()
            }
            return
        }

        var folderRoms: [URL: [URL]] = [:]
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            let parent = fileURL.deletingLastPathComponent()
            folderRoms[parent, default: []].append(fileURL)
        }

        for (folder, roms) in folderRoms {
            let primaryRom: URL
            if let cue = roms.first(where: { $0.pathExtension.lowercased() == "cue" }) {
                primaryRom = cue
            } else if let chd = roms.first(where: { $0.pathExtension.lowercased() == "chd" }) {
                primaryRom = chd
            } else if let iso = roms.first(where: { $0.pathExtension.lowercased() == "iso" }) {
                primaryRom = iso
            } else {
                primaryRom = roms[0]
            }

            guard !existingPaths.contains(primaryRom.path) else { continue }

            let title = (folder.lastPathComponent != "ROM's") ? folder.lastPathComponent : primaryRom.deletingPathExtension().lastPathComponent
            let console = Self.detectConsole(url: primaryRom, title: title)

            var coverPath: String? = nil
            for cName in ["cover.jpg", "cover.png", "\(title).jpg", "\(title).png"] {
                let cURL = folder.appendingPathComponent(cName)
                if fm.fileExists(atPath: cURL.path) {
                    coverPath = cURL.path
                    break
                }
            }

            let item = GameItem(
                title: title,
                consoleName: console,
                fileName: primaryRom.path,
                coverImagePath: coverPath
            )
            currentGames.append(item)
            existingPaths.insert(primaryRom.path)
            updated = true

            if coverPath == nil {
                Task {
                    await fetchMetadata(for: item.id)
                }
            }
        }

        if updated {
            self.games = currentGames
            saveLibrary()
        }
    }

    func renameGame(_ game: GameItem, to newName: String) {
        guard let index = games.firstIndex(of: game), !newName.isEmpty else { return }
        let oldGame = games[index]
        games[index].title = newName

        let fileURL = URL(fileURLWithPath: oldGame.fileName)
        let oldFolder = fileURL.deletingLastPathComponent()

        if oldFolder.lastPathComponent != "ROM's" && oldFolder.path.contains("ROM's") {
            let parentFolder = oldFolder.deletingLastPathComponent()
            let newFolder = parentFolder.appendingPathComponent(newName, isDirectory: true)

            if !FileManager.default.fileExists(atPath: newFolder.path) {
                do {
                    try FileManager.default.moveItem(at: oldFolder, to: newFolder)
                    let newRomURL = newFolder.appendingPathComponent(fileURL.lastPathComponent)
                    games[index].fileName = newRomURL.path
                    if let oldCover = games[index].coverImagePath {
                        let coverFileName = URL(fileURLWithPath: oldCover).lastPathComponent
                        games[index].coverImagePath = newFolder.appendingPathComponent(coverFileName).path
                    }
                } catch {
                    print("[ViewModel] Rename folder failed: \(error)")
                }
            }
        }
        saveLibrary()
    }

    func removeCoverImage(for game: GameItem) {
        guard let index = games.firstIndex(of: game) else { return }
        objectWillChange.send()
        if let path = games[index].coverImagePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        let gameFolder = URL(fileURLWithPath: games[index].fileName).deletingLastPathComponent()
        for name in ["cover.jpg", "cover.png", "cover.jpeg"] {
            let file = gameFolder.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: file)
        }
        games[index].coverImagePath = nil
        saveLibrary()
    }

    func updateCoverImageData(for game: GameItem, imageData: Data) {
        let gameFolder = URL(fileURLWithPath: game.fileName).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
        let imgDest = gameFolder.appendingPathComponent("cover.jpg")

        do {
            try imageData.write(to: imgDest)
            if let index = games.firstIndex(of: game) {
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
                    let gameFolder = URL(fileURLWithPath: game.fileName).deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
                    let imgDest = gameFolder.appendingPathComponent("cover.jpg")
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
