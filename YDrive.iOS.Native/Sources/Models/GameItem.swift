import Foundation

// Represents a ROM / game entry in the library
struct GameItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var consoleName: String
    var fileName: String
    var developer: String?
    var releaseYear: String?
    var summary: String?
    var coverImagePath: String?

    init(
        id: UUID = UUID(),
        title: String,
        consoleName: String,
        fileName: String,
        developer: String? = nil,
        releaseYear: String? = nil,
        summary: String? = nil,
        coverImagePath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.consoleName = consoleName
        self.fileName = fileName
        self.developer = developer
        self.releaseYear = releaseYear
        self.summary = summary
        self.coverImagePath = coverImagePath
    }
}
