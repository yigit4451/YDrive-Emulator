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
        let name = url.deletingPathExtension().lastPathComponent
        let item = GameItem(
            title: name,
            consoleName: "SEGA Genesis",
            fileName: url.lastPathComponent
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
