import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class GameLibraryViewModel: ObservableObject {
    @Published var games: [GameItem] = []
    @Published var searchText: String = ""
    @Published var isFilePickerPresented: Bool = false

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
        let item = GameItem(
            title: name,
            consoleName: "SEGA Genesis",
            fileName: dest.path   // store the full absolute path
        )
        games.append(item)
    }

    func deleteGame(_ game: GameItem) {
        games.removeAll { $0.id == game.id }
    }

    func renameGame(_ game: GameItem, to newName: String) {
        if let index = games.firstIndex(of: game) {
            games[index].title = newName
        }
    }
}
