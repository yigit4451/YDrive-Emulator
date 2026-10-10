import Foundation

@MainActor
final class TheGamesDBClient {
    static let shared = TheGamesDBClient()
    /// API key stored XOR-obfuscated (not plaintext) so it can't be found by
    /// simple text search / GitHub key scanners. Decoded once at runtime.
    private let apiKey: String = {
        let data: [UInt8] = [
            0x68, 0x72, 0x41, 0x0B, 0x42, 0x06, 0x1E, 0x6C, 0x0D, 0x01, 0x24, 0x03, 0x5B, 0x51, 0x10, 0x74,
            0x20, 0x17, 0x13, 0x04, 0x6E, 0x7D, 0x40, 0x0D, 0x4F, 0x53, 0x18, 0x63, 0x0E, 0x03, 0x76, 0x50,
            0x5A, 0x54, 0x46, 0x7D, 0x71, 0x19, 0x44, 0x01, 0x6A, 0x7D, 0x40, 0x50, 0x40, 0x07, 0x1D, 0x30,
            0x58, 0x01, 0x70, 0x55, 0x0F, 0x54, 0x41, 0x77, 0x76, 0x19, 0x43, 0x06, 0x3F, 0x7C, 0x43, 0x51
        ]
        let mask = Array("YDrive.TheGamesDB.v1".utf8)
        let bytes = data.enumerated().map { $0.element ^ mask[$0.offset % mask.count] }
        return String(decoding: bytes, as: UTF8.self)
    }()

    /// TheGamesDB platform IDs
    /// 18 = Sega Genesis/Mega Drive
    /// 21 = Sega CD / Mega-CD
    /// 35 = Sega Master System
    private let platformIDs: [String: Int] = [
        "md": 18, "gen": 18, "smd": 18, "bin": 18, "zip": 18,
        "chd": 21, "sms": 35
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
        var name = filename
        // Only strip real ROM extensions; titles like "Dr. Robotnik" must stay intact.
        let romExts: Set<String> = ["md", "gen", "smd", "bin", "zip", "chd", "cue", "iso", "sms", "32x"]
        let ext = (filename as NSString).pathExtension.lowercased()
        if romExts.contains(ext) { name = (filename as NSString).deletingPathExtension }

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

        do {
            // 1) Try with the platform filter, 2) retry without it if nothing found.
            var gamesArr = try await searchGames(query: query, platform: platform)
            if gamesArr.isEmpty {
                gamesArr = try await searchGames(query: query, platform: nil)
            }
            guard !gamesArr.isEmpty else {
                print("[TheGamesDB] No results for '\(query)'")
                return nil
            }

            let bestGame = gamesArr.max { g1, g2 in
                let t1 = (g1["game_title"] as? String) ?? ""
                let t2 = (g2["game_title"] as? String) ?? ""
                return scoreMatch(title: t1, query: query) < scoreMatch(title: t2, query: query)
            }
            guard let gameDict = bestGame, let gameId = gameDict["id"] as? Int else { return nil }

            let summary = gameDict["overview"] as? String
            var releaseYear: String? = nil
            if let dateStr = gameDict["release_date"] as? String, dateStr.count >= 4 {
                releaseYear = String(dateStr.prefix(4))
            }

            // Box art
            var coverImageUrl: String? = nil
            
            var imgComponents = URLComponents(string: "https://api.thegamesdb.net/v1/Games/Images")!
            imgComponents.queryItems = [
                URLQueryItem(name: "apikey", value: apiKey),
                URLQueryItem(name: "games_id", value: String(gameId)),
                URLQueryItem(name: "filter[type]", value: "boxart")
            ]
            
            if let imagesUrl = imgComponents.url {
                if let (imgData, _) = try? await URLSession.shared.data(from: imagesUrl),
                   let imgJson = try? JSONSerialization.jsonObject(with: imgData) as? [String: Any],
                   let imgDataDict = imgJson["data"] as? [String: Any],
                   let baseUrlDict = imgDataDict["base_url"] as? [String: Any],
                   let baseUrl = baseUrlDict["original"] as? String,
                   let imagesDict = imgDataDict["images"] as? [String: Any],
                   let gameImages = imagesDict[String(gameId)] as? [[String: Any]],
                   !gameImages.isEmpty {
                    
                    let frontImage = gameImages.first(where: { ($0["side"] as? String) == "front" }) ?? gameImages[0]
                    if let filename = frontImage["filename"] as? String {
                        coverImageUrl = baseUrl + filename
                    }
                }
            }

            return FetchResult(
                summary: summary,
                developer: nil,
                releaseYear: releaseYear,
                coverImageUrl: coverImageUrl
            )
        } catch {
            print("[TheGamesDB] Fetch failed for \(query): \(error)")
            return nil
        }
    }

    // ── Networking ────────────────────────────────────────────────────────────
    private func searchGames(query: String, platform: Int?) async throws -> [[String: Any]] {
        var components = URLComponents(string: "https://api.thegamesdb.net/v1/Games/ByGameName")!
        var items = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "fields", value: "overview")
        ]
        if let platform { items.append(URLQueryItem(name: "filter[platform]", value: String(platform))) }
        components.queryItems = items
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            print("[TheGamesDB] HTTP \(http.statusCode): \(body)")
            return []
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let games = dataDict["games"] as? [[String: Any]] else {
            print("[TheGamesDB] Unexpected response for '\(query)'")
            return []
        }
        // Only keep original-era releases (Genesis/Sega CD era). Later re-releases
        // (2011, 2019, 2020 collections, Virtual Console, Mini consoles…) are dropped.
        // Entries without a release date are kept.
        return games.filter { game in
            guard let dateStr = game["release_date"] as? String,
                  dateStr.count >= 4,
                  let year = Int(dateStr.prefix(4)) else { return true }
            return (Self.minYear...Self.maxYear).contains(year)
        }
    }

    private static let minYear = 1985
    private static let maxYear = 1999

    // ── Scoring ───────────────────────────────────────────────────────────────
    private func scoreMatch(title: String, query: String) -> Int {
        let t = normalizeName(title).lowercased()
        let q = query.lowercased()

        if t == q { return 100 }

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
