import Foundation

@MainActor
final class TheGamesDBClient {
    static let shared = TheGamesDBClient()
    private let apiKey = "163b4c08edcb64c0b9e5792d9667ff117159372039296b3d0d74b1234757f818"

    /// TheGamesDB platform IDs
    /// 18 = Sega Genesis/Mega Drive
    /// 21 = Sega CD / Mega-CD
    /// 35 = Sega Master System
    private let platformIDs: [String: Int] = [
        "md": 18, "gen": 18, "smd": 18, "bin": 18, "zip": 18,
        "chd": 21
    ]

    private init() {}

    // ── Platform ID resolution ────────────────────────────────────────────────
    /// Determines the platform ID from the file extension.
    /// Defaults to Genesis (18) if unknown.
    func platformID(for filename: String) -> Int {
        let ext = (filename as NSString).pathExtension.lowercased()
        return platformIDs[ext] ?? 18
    }

    // ── Name normalization ────────────────────────────────────────────────────
    func normalizeName(_ filename: String) -> String {
        var name = (filename as NSString).deletingPathExtension

        // Remove region/version tags like (World), (USA), [!], etc.
        name = name.replacingOccurrences(of: "\\s*\\(.*?\\)", with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: "\\s*\\[.*?\\]", with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: "_", with: " ")
        name = name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ── Fetch ─────────────────────────────────────────────────────────────────
    struct FetchResult {
        let summary: String?
        let developer: String?
        let releaseYear: String?
        let coverImageUrl: String?
    }

    func fetchMetadata(for rawName: String) async -> FetchResult? {
        let query    = normalizeName(rawName)
        let platform = platformID(for: rawName)
        guard !query.isEmpty else { return nil }

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string:
                "https://api.thegamesdb.net/v1/Games/ByGameName"
                + "?apikey=\(apiKey)"
                + "&name=\(encodedQuery)"
                + "&filter%5Bplatform%5D=\(platform)"
                + "&fields=overview,developers,publishers&lang=en"
              )
        else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            guard let response = try? decoder.decode(GamesDBResponse.self, from: data),
                  !response.data.games.isEmpty else { return nil }

            // Best match by title scoring — penalise cross-platform mismatches
            let bestGame = response.data.games.max { g1, g2 in
                scoreMatch(title: g1.game_title, query: query) <
                scoreMatch(title: g2.game_title, query: query)
            }
            guard let game = bestGame else { return nil }

            // Release year
            var releaseYear: String? = nil
            if let d = game.release_date, d.count >= 4 { releaseYear = String(d.prefix(4)) }

            // Developer
            var developerName: String? = nil
            if let devId = game.developers?.first, let devs = response.include?.developer {
                developerName = devs[String(devId)]?.name
            }

            // Box art — front face only
            var coverImageUrl: String? = nil
            if let imagesUrl = URL(string:
                "https://api.thegamesdb.net/v1/Games/Images"
                + "?apikey=\(apiKey)"
                + "&games_id=\(game.id)"
                + "&filter%5Btype%5D=boxart"
            ) {
                if let (imgData, _) = try? await URLSession.shared.data(from: imagesUrl),
                   let imgResponse = try? decoder.decode(GamesDBImagesResponse.self, from: imgData) {
                    let baseUrl = imgResponse.data.base_url.original
                    // Prefer "front" side; fallback to first available
                    if let boxart = imgResponse.data.images[String(game.id)]?.first(where: { $0.side == "front" })
                        ?? imgResponse.data.images[String(game.id)]?.first {
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

    // ── Scoring ───────────────────────────────────────────────────────────────
    private func scoreMatch(title: String, query: String) -> Int {
        let t = normalizeName(title).lowercased()
        let q = query.lowercased()

        if t == q { return 100 }

        // Penalise if critical identifiers mismatch (sequel numbers, platform hints)
        let identifiers = ["2", "3", "4", "5", "ii", "iii", "iv", "v",
                           "cd", "3d", "32x", "plus", "deluxe", "& knuckles"]
        for id in identifiers {
            let tHas = t.components(separatedBy: .whitespaces).contains(id) || (id.contains(" ") && t.contains(id))
            let qHas = q.components(separatedBy: .whitespaces).contains(id) || (id.contains(" ") && q.contains(id))
            if tHas != qHas { return -100 }
        }

        if t.contains(q) || q.contains(t) { return 50 }
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
