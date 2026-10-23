import Foundation
import UIKit

// Represents a ROM / game entry in the library
struct GameItem: Identifiable, Hashable, Codable {
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

    /// Resolves the cover image data even if the container UUID or folder structure changed.
    func resolveCoverImage() -> UIImage? {
        if let coverPath = coverImagePath {
            if let img = UIImage(contentsOfFile: coverPath) {
                return img
            }
            let filename = URL(fileURLWithPath: coverPath).lastPathComponent
            let gameFolder = URL(fileURLWithPath: fileName).deletingLastPathComponent()
            let inFolder = gameFolder.appendingPathComponent(filename).path
            if let img = UIImage(contentsOfFile: inFolder) {
                return img
            }
        }

        // Check standard cover images in the game's folder
        let gameFolder = URL(fileURLWithPath: fileName).deletingLastPathComponent()
        for candidate in ["cover.jpg", "cover.png", "cover.jpeg", "\(title).jpg", "\(title).png"] {
            let path = gameFolder.appendingPathComponent(candidate).path
            if let img = UIImage(contentsOfFile: path) {
                return img
            }
        }

        // Fallback: check in Documents root
        if let coverPath = coverImagePath,
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let filename = URL(fileURLWithPath: coverPath).lastPathComponent
            let inDocs = docs.appendingPathComponent(filename).path
            if let img = UIImage(contentsOfFile: inDocs) {
                return img
            }
        }

        return nil
    }
}
