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
            self.games = decoded
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
        let ext = url.pathExtension.lowercased()
        
        var item = GameItem(
            title: name,
            consoleName: ext == "chd" ? "SEGA CD" : "SEGA Genesis",
            fileName: dest.path   // store the full absolute path
        )
        let id = item.id
        games.append(item)
        saveLibrary()

        Task {
            if let result = await TheGamesDBClient.shared.fetchMetadata(for: name) {
                if let index = self.games.firstIndex(where: { $0.id == id }) {
                    if let dev = result.developer { self.games[index].developer = dev }
                    if let year = result.releaseYear { self.games[index].releaseYear = year }
                    if let sum = result.summary { self.games[index].summary = sum }
                    self.saveLibrary()
                }
                
                if let imgUrlString = result.coverImageUrl, let imgUrl = URL(string: imgUrlString) {
                    if let (data, _) = try? await URLSession.shared.data(from: imgUrl) {
                        let imgName = UUID().uuidString + ".jpg"
                        let imgDest = docs.appendingPathComponent(imgName)
                        try? data.write(to: imgDest)
                        if let index = self.games.firstIndex(where: { $0.id == id }) {
                            self.games[index].coverImagePath = imgDest.path
                            self.saveLibrary()
                        }
                    }
                }
            }
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

    func refreshMetadata() {
        for (i, game) in games.enumerated() {
            let id = game.id
            let name = game.title
            
            Task {
                if let result = await TheGamesDBClient.shared.fetchMetadata(for: name) {
                    if let index = self.games.firstIndex(where: { $0.id == id }) {
                        if let dev = result.developer { self.games[index].developer = dev }
                        if let year = result.releaseYear { self.games[index].releaseYear = year }
                        if let sum = result.summary { self.games[index].summary = sum }
                        self.saveLibrary()
                    }
                    
                    if let imgUrlString = result.coverImageUrl, let imgUrl = URL(string: imgUrlString) {
                        if let (data, _) = try? await URLSession.shared.data(from: imgUrl) {
                            let imgName = UUID().uuidString + ".jpg"
                            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let imgDest = docs.appendingPathComponent(imgName)
                            try? data.write(to: imgDest)
                            if let index = self.games.firstIndex(where: { $0.id == id }) {
                                self.games[index].coverImagePath = imgDest.path
                                self.saveLibrary()
                            }
                        }
                    }
                }
            }
        }
    }
}
