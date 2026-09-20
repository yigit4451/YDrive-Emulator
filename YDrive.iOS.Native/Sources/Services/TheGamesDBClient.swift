import Foundation

@MainActor
final class TheGamesDBClient {
    static let shared = TheGamesDBClient()
    private let apiKey = "163b4c08edcb64c0b9e5792d9667ff117159372039296b3d0d74b1234757f818"
    // Sega Genesis = 18, Sega CD = 20
    private let platforms = "18,20"

    private init() {}

    /// Normalizes ROM filename for search
    /// E.g., "Sonic The Hedgehog 2 (World) [!].md" -> "Sonic The Hedgehog 2"
    func normalizeName(_ filename: String) -> String {
        var name = filename
        
        // Remove known ROM extensions
        let extensions = [".md", ".bin", ".gen", ".smd", ".zip"]
        for ext in extensions {
            if name.lowercased().hasSuffix(ext) {
                name = String(name.dropLast(ext.count))
            }
        }
        
        // Remove tags like (World), (USA), [!], [b1], etc. using Regex
        name = name.replacingOccurrences(of: "\\s*\\(.*?\\)", with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: "\\s*\\[.*?\\]", with: "", options: .regularExpression)
        
        // Replace underscores with spaces
        name = name.replacingOccurrences(of: "_", with: " ")
        
        // Clean up multiple spaces
        name = name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct FetchResult {
        let summary: String?
        let developer: String?
        let releaseYear: String?
        let coverImageUrl: String? // We provide the full URL, the ViewModel handles downloading
    }

    func fetchMetadata(for rawName: String) async -> FetchResult? {
        let query = normalizeName(rawName)
        guard !query.isEmpty else { return nil }

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.thegamesdb.net/v1/Games/ByGameName?apikey=\(apiKey)&name=\(encodedQuery)&filter%5Bplatform%5D=\(platforms)&fields=overview,developers,publishers&lang=en") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            let decoder = JSONDecoder()
            guard let response = try? decoder.decode(GamesDBResponse.self, from: data),
                  !response.data.games.isEmpty else {
                return nil
            }

            // Find best match based on scoring
            let bestGame = response.data.games.max { g1, g2 in
                scoreMatch(title: g1.game_title, query: query) < scoreMatch(title: g2.game_title, query: query)
            }
            
            guard let game = bestGame else { return nil }

            // Extract Release Year
            var releaseYear: String? = nil
            if let releaseDate = game.release_date, releaseDate.count >= 4 {
                releaseYear = String(releaseDate.prefix(4))
            }

            // Extract Developer
            var developerName: String? = nil
            if let devId = game.developers?.first, let devs = response.include?.developer {
                developerName = devs[String(devId)]?.name
            }

            // Fetch Boxart (Requires separate call)
            var coverImageUrl: String? = nil
            if let imagesUrl = URL(string: "https://api.thegamesdb.net/v1/Games/Images?apikey=\(apiKey)&games_id=\(game.id)&filter%5Btype%5D=boxart") {
                if let (imgData, _) = try? await URLSession.shared.data(from: imagesUrl),
                   let imgResponse = try? decoder.decode(GamesDBImagesResponse.self, from: imgData) {
                    
                    if let boxart = imgResponse.data.images[String(game.id)]?.first(where: { $0.side == "front" }) {
                        let baseUrl = imgResponse.data.base_url.original
                        coverImageUrl = baseUrl + boxart.filename
                    }
                }
            }

            return FetchResult(
                summary: game.overview,
                developer: developerName,
                releaseYear: releaseYear,
                coverImageUrl: coverImageUrl
            )
        } catch {
            print("[TheGamesDB] Fetch failed for \(query): \(error)")
            return nil
        }
    }

    private func scoreMatch(title: String, query: String) -> Int {
        let normalizedTitle = normalizeName(title).lowercased()
        let normalizedQuery = query.lowercased()
        
        if normalizedTitle == normalizedQuery {
            return 100 // Exact match
        }
        
        // Penalize if sequel numbers / key identifiers don't match
        let digitsAndRoman = ["2", "3", "4", "5", "ii", "iii", "iv", "v", "& knuckles", "cd", "3d", "32x", "plus", "deluxe"]
        for identifier in digitsAndRoman {
            let titleHasIt = normalizedTitle.contains(identifier)
            let queryHasIt = normalizedQuery.contains(identifier)
            
            // If one has a critical identifier and the other doesn't, huge penalty
            if titleHasIt != queryHasIt {
                // Ensure it's isolated as a word, e.g. "Sonic 2" vs "Sonic 2006"
                let titleWords = normalizedTitle.components(separatedBy: .whitespaces)
                let queryWords = normalizedQuery.components(separatedBy: .whitespaces)
                
                if titleWords.contains(identifier) || queryWords.contains(identifier) || identifier.contains(" ") {
                    return -100 
                }
            }
        }
        
        // Basic substring match fallback
        if normalizedTitle.contains(normalizedQuery) || normalizedQuery.contains(normalizedTitle) {
            return 50
        }
        
        return 0
    }
}

// MARK: - Models
fileprivate struct GamesDBResponse: Decodable {
    let data: GamesDBData
    let include: GamesDBInclude?
    
    struct GamesDBData: Decodable {
        let games: [GamesDBGame]
    }
    
    struct GamesDBGame: Decodable {
        let id: Int
        let game_title: String
        let release_date: String?
        let overview: String?
        let developers: [Int]?
    }
    
    struct GamesDBInclude: Decodable {
        let developer: [String: GamesDBDeveloper]?
    }
    
    struct GamesDBDeveloper: Decodable {
        let name: String
    }
}

fileprivate struct GamesDBImagesResponse: Decodable {
    let data: GamesDBImageData
    
    struct GamesDBImageData: Decodable {
        let base_url: BaseUrlInfo
        let images: [String: [GameImage]]
    }
    
    struct BaseUrlInfo: Decodable {
        let original: String
    }
    
    struct GameImage: Decodable {
        let type: String
        let side: String?
        let filename: String
    }
}
