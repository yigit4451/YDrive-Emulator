using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using SegaEmulator.Helpers;
using SegaEmulator.Models;

namespace SegaEmulator.Services;

public class GameMetadataResult
{
    public string Title { get; set; } = string.Empty;
    public string ReleaseYear { get; set; } = "Bilinmiyor";
    public string Developer { get; set; } = "Bilinmiyor";
    public string Summary { get; set; } = "Oyun hakkında özet bilgi bulunamadı.";
    public string ArtworkPath { get; set; } = string.Empty;
}

/// <summary>
/// İnternet üzerinden GitHub Libretro Raw CDN ve Wikipedia kaynaklarından kapak resmi (Boxart),
/// çıkış yılı, yapımcı ve oyun özeti bilgilerini çeken servis.
/// </summary>
public class GameMetadataService
{
    private static readonly HttpClient HttpClient = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(8)
    };

    private readonly string _coversDirectory;

    // TODO: TheGamesDB API anahtarınızı buraya girin.
    // TheGamesDB API kullanımı ücretsizdir ancak https://thegamesdb.net/ adresinden kayıt olup API Key almanız gerekir.
    private const string TheGamesDbApiKey = "163b4c08edcb64c0b9e5792d9667ff117159372039296b3d0d74b1234757f818";

    public GameMetadataService()
    {
        HttpClient.DefaultRequestHeaders.UserAgent.ParseAdd("YDrive-Emulator/1.0 (SEGA Consoles Emulator)");

        // Güvenli Dizin Yapısı: LocalApplicationData/YDrive/Covers
        string appDataCovers = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YDrive", "Covers");

        try
        {
            Directory.CreateDirectory(appDataCovers);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Covers dizini oluşturulurken hata: {ex.Message}");
        }

        _coversDirectory = appDataCovers;
    }

    public async Task<GameMetadataResult> FetchMetadataAsync(string rawFileName, string gameId, SystemType sysType = SystemType.Genesis, bool forceRefresh = false)
    {
        string cleanTitle = RomNameCleaner.CleanTitle(rawFileName);
        var result = new GameMetadataResult
        {
            Title = cleanTitle
        };

        if (string.IsNullOrWhiteSpace(cleanTitle)) return result;

        bool hasKnownData = false;
        // Bilinen oyun veritabanı kontrolü (Sadece Genesis oyunları için geçerlidir)
        KnownGameInfo? known = null;
        if (sysType == SystemType.Genesis)
        {
            known = KnownGamesDatabase.GetInfo(cleanTitle);
        }

        if (known != null)
        {
            hasKnownData = true;
            result.ReleaseYear = known.ReleaseYear;
            result.Developer = known.Developer;
            
            string lang = System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
            if (lang == "tr")
            {
                if (!string.IsNullOrEmpty(known.Summary))
                    result.Summary = known.Summary;
            }
            else
            {
                if (!string.IsNullOrEmpty(known.SummaryEn))
                    result.Summary = known.SummaryEn;
            }
        }

        try
        {
            // 1. TheGamesDB API'den Veri ve Kapak Çekmeye Çalış
            bool gamesDbSuccess = await TryFetchFromTheGamesDbAsync(cleanTitle, rawFileName, gameId, result, hasKnownData, forceRefresh, sysType);

            // 2. TheGamesDB'den bulunamazsa Libretro ve Wikipedia (Fallback) kullan
            if (!gamesDbSuccess)
            {
                await TryFetchLibretroBoxartAsync(cleanTitle, rawFileName, gameId, result, forceRefresh, sysType);

                if (!hasKnownData)
                {
                    await TryFetchFromWikipediaAsync(cleanTitle, result, forceRefresh, sysType);
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Metadata çekilirken genel hata: {ex.Message}");
            DiagnosticLog.WriteError("MetadataService", $"Metadata çekilirken hata: {ex.Message}");
        }

        return result;
    }

    private async Task<bool> TryFetchFromTheGamesDbAsync(string cleanTitle, string rawFileName, string gameId, GameMetadataResult result, bool hasKnownData, bool forceRefresh, SystemType sysType)
    {
        if (string.IsNullOrWhiteSpace(TheGamesDbApiKey))
        {
            Debug.WriteLine("[TheGamesDB] API Key boş, TheGamesDB araması atlanıyor.");
            return false;
        }

        try
        {
            var searchQueries = new List<string> { cleanTitle };

            // Kullanıcıların sık yaptığı isimlendirmeler için özel düzeltmeler
            string lowerTitle = cleanTitle.ToLowerInvariant();
            if (lowerTitle == "sonic 1") searchQueries.Add("Sonic the Hedgehog");
            if (lowerTitle == "sonic 2") searchQueries.Add("Sonic the Hedgehog 2");
            if (lowerTitle == "sonic 3") searchQueries.Add("Sonic the Hedgehog 3");
            if (lowerTitle == "mortal kombat 1") searchQueries.Add("Mortal Kombat");

            var words = cleanTitle.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (words.Length > 2)
            {
                searchQueries.Add($"{words[0]} {words[1]}"); // e.g., "Sonic The"
            }
            if (words.Length > 1)
            {
                searchQueries.Add(words[0]); // e.g., "Sonic"
            }

            string platforms = sysType switch
            {
                SystemType.SegaCD => "21",
                SystemType.Sega32X => "33",
                SystemType.MasterSystem => "35",
                SystemType.GameGear => "20",
                _ => "18"
            };

            foreach (var query in searchQueries)
            {
                string searchUrl = $"https://api.thegamesdb.net/v1/Games/ByGameName?apikey={TheGamesDbApiKey}&name={Uri.EscapeDataString(query)}&filter%5Bplatform%5D={platforms}&fields=overview,developers,publishers&lang=en";
                using var ctsSrch = new CancellationTokenSource(TimeSpan.FromSeconds(8));
                var searchResponse = await HttpClient.GetAsync(searchUrl, ctsSrch.Token);

                if (!searchResponse.IsSuccessStatusCode) continue;

                using var doc = await JsonDocument.ParseAsync(await searchResponse.Content.ReadAsStreamAsync(ctsSrch.Token));
                var root = doc.RootElement;

                if (root.TryGetProperty("data", out var dataProp) && dataProp.TryGetProperty("games", out var gamesArray))
                {
                    int resultCount = gamesArray.GetArrayLength();
                    Debug.WriteLine($"[TheGamesDB] Aranan: '{query}' -> Sonuç: {resultCount}");

                    if (resultCount > 0)
                    {
                        int targetPlatformId = int.Parse(platforms);
                        var nodes = new List<JsonElement>();
                        foreach (var node in gamesArray.EnumerateArray())
                        {
                            if (node.TryGetProperty("platform", out var platformProp) && platformProp.ValueKind == JsonValueKind.Number)
                            {
                                if (platformProp.GetInt32() == targetPlatformId)
                                {
                                    nodes.Add(node);
                                }
                            }
                        }

                        if (nodes.Count == 0) continue;

                        JsonElement gameNode = nodes[0];
                        bool exactMatchFound = false;

                        // Tam eşleşme aranırken İngilizce bölgeyi (region_id=6) önceliklendir
                        foreach (var node in nodes)
                        {
                            if (node.TryGetProperty("game_title", out var titleProp) && titleProp.ValueKind == JsonValueKind.String)
                            {
                                string? t = titleProp.GetString();
                                bool titleMatches = (t != null && t.Equals(cleanTitle, StringComparison.OrdinalIgnoreCase))
                                                 || (t != null && t.Equals(query, StringComparison.OrdinalIgnoreCase));

                                if (titleMatches)
                                {
                                    // Boş overview veya 1970 tarihi olan (Portekizce/Brazil bölgesi) kayıtları atla
                                    bool hasGoodOverview = node.TryGetProperty("overview", out var ov) &&
                                                           ov.ValueKind == JsonValueKind.String &&
                                                           !string.IsNullOrWhiteSpace(ov.GetString());
                                    bool has1970Date = node.TryGetProperty("release_date", out var rd) &&
                                                       rd.ValueKind == JsonValueKind.String &&
                                                       (rd.GetString() ?? "").StartsWith("1970");

                                    // İngilizce bölge (region_id=6) tam eşleşme bulursa hemen seç
                                    bool isEnglishRegion = node.TryGetProperty("region_id", out var regionProp) &&
                                                           regionProp.ValueKind == JsonValueKind.Number &&
                                                           regionProp.GetInt32() == 6;

                                    if (titleMatches && isEnglishRegion && hasGoodOverview && !has1970Date)
                                    {
                                        gameNode = node;
                                        exactMatchFound = true;
                                        break;
                                    }
                                    else if (titleMatches && !exactMatchFound && hasGoodOverview && !has1970Date)
                                    {
                                        gameNode = node;
                                        exactMatchFound = true;
                                    }
                                }
                            }
                        }

                        // Tam eşleşme yoksa: İngilizce bölgeyi önce, sonra alfabetik sırayla diz
                        if (!exactMatchFound)
                        {
                            nodes.Sort((a, b) =>
                            {
                                // İngilizce bölge (region_id=6) önce gelsin
                                int rA = a.TryGetProperty("region_id", out var rpA) && rpA.ValueKind == JsonValueKind.Number ? rpA.GetInt32() : 99;
                                int rB = b.TryGetProperty("region_id", out var rpB) && rpB.ValueKind == JsonValueKind.Number ? rpB.GetInt32() : 99;
                                int engA = rA == 6 ? 0 : 1;
                                int engB = rB == 6 ? 0 : 1;
                                if (engA != engB) return engA.CompareTo(engB);

                                // 1970 tarihli (Portekizce) kayıtları sona at
                                bool d1970A = a.TryGetProperty("release_date", out var rdA) && rdA.ValueKind == JsonValueKind.String && (rdA.GetString() ?? "").StartsWith("1970");
                                bool d1970B = b.TryGetProperty("release_date", out var rdB) && rdB.ValueKind == JsonValueKind.String && (rdB.GetString() ?? "").StartsWith("1970");
                                if (d1970A != d1970B) return d1970A ? 1 : -1;

                                string tA = a.TryGetProperty("game_title", out var pA) ? pA.GetString() ?? "" : "";
                                string tB = b.TryGetProperty("game_title", out var pB) ? pB.GetString() ?? "" : "";
                                int lenCmp = tA.Length.CompareTo(tB.Length);
                                if (lenCmp != 0) return lenCmp;
                                return string.Compare(tA, tB, StringComparison.OrdinalIgnoreCase);
                            });
                            gameNode = nodes[0];
                        }

                        int tdbGameId = gameNode.GetProperty("id").GetInt32();

                        if (!hasKnownData)
                        {
                            if (gameNode.TryGetProperty("release_date", out var releaseDateProp) && releaseDateProp.ValueKind == JsonValueKind.String)
                            {
                                var releaseStr = releaseDateProp.GetString();
                                if (!string.IsNullOrEmpty(releaseStr) && releaseStr.Length >= 4)
                                {
                                    result.ReleaseYear = releaseStr.Substring(0, 4);
                                }
                            }

                            if (gameNode.TryGetProperty("overview", out var overviewProp))
                            {
                                if (overviewProp.ValueKind == JsonValueKind.String)
                                {
                                    var overviewStr = overviewProp.GetString();
                                    if (!string.IsNullOrEmpty(overviewStr))
                                    {
                                        result.Summary = overviewStr;
                                    }
                                }
                                else if (overviewProp.ValueKind == JsonValueKind.Array)
                                {
                                    // Eğer yanıt bir dizi olarak geliyorsa İngilizce (veya Türkçe) olan açıklamayı seçelim
                                    foreach (var translationNode in overviewProp.EnumerateArray())
                                    {
                                        if (translationNode.TryGetProperty("language", out var langProp) && langProp.ValueKind == JsonValueKind.String)
                                        {
                                            string lang = langProp.GetString()?.ToLowerInvariant() ?? "";
                                            if (lang == "en" || lang == "tr")
                                            {
                                                if (translationNode.TryGetProperty("text", out var textProp) && textProp.ValueKind == JsonValueKind.String)
                                                {
                                                    var textStr = textProp.GetString();
                                                    if (!string.IsNullOrEmpty(textStr))
                                                    {
                                                        result.Summary = textStr;
                                                        if (lang == "tr") break; // Türkçe bulduysak daha öncelikli
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            string devName = "";
                            if (gameNode.TryGetProperty("developers", out var devArray) && devArray.GetArrayLength() > 0)
                            {
                                int devId = devArray[0].GetInt32();
                                string devUrl = $"https://api.thegamesdb.net/v1/Developers?apikey={TheGamesDbApiKey}&id={devId}";
                                try
                                {
                                    using var ctsDev = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                                    var devResponse = await HttpClient.GetAsync(devUrl, ctsDev.Token);
                                    if (devResponse.IsSuccessStatusCode)
                                    {
                                        using var devDoc = await JsonDocument.ParseAsync(await devResponse.Content.ReadAsStreamAsync(ctsDev.Token));
                                        if (devDoc.RootElement.TryGetProperty("data", out var devData) &&
                                            devData.TryGetProperty("developers", out var devList) &&
                                            devList.ValueKind == JsonValueKind.Object)
                                        {
                                            if (devList.TryGetProperty(devId.ToString(), out var specificDev) && specificDev.TryGetProperty("name", out var nameProp))
                                            {
                                                devName = nameProp.GetString() ?? "";
                                            }
                                        }
                                    }
                                }
                                catch { /* Yut */ }
                            }

                            string pubName = "";
                            if (gameNode.TryGetProperty("publishers", out var pubArray) && pubArray.GetArrayLength() > 0)
                            {
                                int pubId = pubArray[0].GetInt32();
                                string pubUrl = $"https://api.thegamesdb.net/v1/Publishers?apikey={TheGamesDbApiKey}&id={pubId}";
                                try
                                {
                                    using var ctsPub = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                                    var pubResponse = await HttpClient.GetAsync(pubUrl, ctsPub.Token);
                                    if (pubResponse.IsSuccessStatusCode)
                                    {
                                        using var pubDoc = await JsonDocument.ParseAsync(await pubResponse.Content.ReadAsStreamAsync(ctsPub.Token));
                                        if (pubDoc.RootElement.TryGetProperty("data", out var pubData) &&
                                            pubData.TryGetProperty("publishers", out var pubList) &&
                                            pubList.ValueKind == JsonValueKind.Object)
                                        {
                                            if (pubList.TryGetProperty(pubId.ToString(), out var specificPub) && specificPub.TryGetProperty("name", out var nameProp))
                                            {
                                                pubName = nameProp.GetString() ?? "";
                                            }
                                        }
                                    }
                                }
                                catch { /* Yut */ }
                            }

                            if (!string.IsNullOrEmpty(devName) && !string.IsNullOrEmpty(pubName) && devName != pubName)
                            {
                                result.Developer = $"{devName} / {pubName}";
                            }
                            else if (!string.IsNullOrEmpty(devName))
                            {
                                result.Developer = devName;
                            }
                            else if (!string.IsNullOrEmpty(pubName))
                            {
                                result.Developer = pubName;
                            }
                        }

                        // Görsel
                        string imagesUrl = $"https://api.thegamesdb.net/v1/Games/Images?apikey={TheGamesDbApiKey}&games_id={tdbGameId}&filter%5Btype%5D=boxart";
                        using var ctsImg = new CancellationTokenSource(TimeSpan.FromSeconds(10));
                        var imgResponse = await HttpClient.GetAsync(imagesUrl, ctsImg.Token);

                        if (imgResponse.IsSuccessStatusCode)
                        {
                            using var imgDoc = await JsonDocument.ParseAsync(await imgResponse.Content.ReadAsStreamAsync(ctsImg.Token));
                            var imgRoot = imgDoc.RootElement;

                            if (imgRoot.TryGetProperty("data", out var imgDataProp))
                            {
                                string baseUrl = imgDataProp.GetProperty("base_url").GetProperty("original").GetString() ?? "";

                                if (imgDataProp.TryGetProperty("images", out var imagesObj) && imagesObj.TryGetProperty(tdbGameId.ToString(), out var gameImagesArray))
                                {
                                    if (gameImagesArray.GetArrayLength() > 0)
                                    {
                                        JsonElement? bestFrontUs = null;
                                        JsonElement? firstFrontBoxart = null;
                                        JsonElement? fallbackBoxart = null;

                                        foreach (var img in gameImagesArray.EnumerateArray())
                                        {
                                            string type = img.TryGetProperty("type", out var tProp) ? (tProp.GetString() ?? "").ToLowerInvariant() : "";
                                            string side = img.TryGetProperty("side", out var sProp) ? (sProp.GetString() ?? "").ToLowerInvariant() : "";
                                            string filenameForCheck = img.TryGetProperty("filename", out var fProp) ? (fProp.GetString() ?? "").ToLowerInvariant() : "";
                                            string regionStr = "";
                                            if (img.TryGetProperty("region", out var rProp))
                                            {
                                                if (rProp.ValueKind == JsonValueKind.String) regionStr = rProp.GetString()?.ToLowerInvariant() ?? "";
                                                else if (rProp.ValueKind == JsonValueKind.Number) regionStr = rProp.GetInt32().ToString();
                                            }

                                            if (filenameForCheck.Contains("/back/") || side == "back")
                                                continue;

                                            if (type == "boxart" && (side == "front" || filenameForCheck.Contains("boxart/front") || filenameForCheck.Contains("front")))
                                            {
                                                if (firstFrontBoxart == null) firstFrontBoxart = img;
                                                
                                                bool isUS = regionStr == "1" || regionStr.Contains("us") || filenameForCheck.Contains("usa");
                                                
                                                if (isUS && bestFrontUs == null) bestFrontUs = img;
                                            }
                                            else if (type == "boxart" && fallbackBoxart == null)
                                            {
                                                fallbackBoxart = img;
                                            }
                                        }

                                        JsonElement? selectedImage = bestFrontUs ?? firstFrontBoxart ?? fallbackBoxart;

                                        if (selectedImage != null)
                                        {
                                            string filename = selectedImage.Value.GetProperty("filename").GetString() ?? "";
                                            string fullImageUrl = baseUrl + filename;

                                            string safeFileName = string.Join("_", $"{cleanTitle}_{sysType}".Split(Path.GetInvalidFileNameChars()));
                                            string localImagePath = await DownloadAndCacheImageAsync(fullImageUrl, safeFileName, gameId, forceRefresh);

                                            if (!string.IsNullOrEmpty(localImagePath))
                                            {
                                                result.ArtworkPath = localImagePath;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        return true;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"TheGamesDB hatası: {ex.Message}");
        }

        return false;
    }

    private async Task TryFetchLibretroBoxartAsync(string cleanTitle, string rawFileName, string gameId, GameMetadataResult result, bool forceRefresh, SystemType sysType)
    {
        try
        {
            string rawNameNoExt = Path.GetFileNameWithoutExtension(rawFileName);
            string safeFileName = string.Join("_", $"{cleanTitle}_{sysType}_Libretro".Split(Path.GetInvalidFileNameChars()));

            var nameCandidates = new List<string>
            {
                cleanTitle,
                rawNameNoExt,
                $"{cleanTitle} (USA, Europe)",
                $"{cleanTitle} (USA)",
                $"{cleanTitle} (Europe)",
                $"{cleanTitle} (Japan)"
            };

            var words = cleanTitle.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (words.Length > 2)
            {
                string firstTwoWords = $"{words[0]} {words[1]}";
                nameCandidates.Add(firstTwoWords);
                nameCandidates.Add($"{firstTwoWords} (USA, Europe)");
                nameCandidates.Add($"{firstTwoWords} (USA)");
            }

            // Title-case variant (her kelimenin ilk harfi büyük): "Sonic The Hedgehog" gibi
            string titleCased = System.Globalization.CultureInfo.InvariantCulture.TextInfo.ToTitleCase(cleanTitle.ToLowerInvariant());
            if (titleCased != cleanTitle)
            {
                nameCandidates.Add(titleCased);
                nameCandidates.Add($"{titleCased} (USA, Europe, Brazil) (En)");
                nameCandidates.Add($"{titleCased} (Europe, Brazil) (En)");
                nameCandidates.Add($"{titleCased} (USA, Europe)");
                nameCandidates.Add($"{titleCased} (USA)");
                nameCandidates.Add($"{titleCased} (Europe)");
                nameCandidates.Add($"{titleCased} (Japan)");
            }
            // Normal adlara da geniş bölge etiketleri ekle
            nameCandidates.Add($"{cleanTitle} (USA, Europe, Brazil) (En)");
            nameCandidates.Add($"{cleanTitle} (Europe, Brazil) (En)");
            nameCandidates.Add($"{rawNameNoExt} (USA, Europe, Brazil) (En)");

            string repoName = sysType switch
            {
                SystemType.MasterSystem => "Sega%20-%20Master%20System%20-%20Mark%20III",
                SystemType.GameGear => "Sega%20-%20Game%20Gear",
                SystemType.SegaCD => "Sega%20-%20Mega-CD%20-%20Sega%20CD",
                SystemType.Sega32X => "Sega%20-%2032X",
                _ => "Sega%20-%20Mega%20Drive%20-%20Genesis"
            };

            // İki farklı host dene: thumbnails.libretro.com (CDN) ve raw.githubusercontent.com
            var baseUrls = new[]
            {
                $"https://thumbnails.libretro.com/{repoName}/Named_Boxarts/",
                $"https://raw.githubusercontent.com/libretro/libretro-database/master/thumbnails/{repoName}/Named_Boxarts/"
            };

            foreach (var baseUrl in baseUrls)
            {
                foreach (var candidate in nameCandidates)
                {
                    string url = $"{baseUrl}{Uri.EscapeDataString(candidate)}.png";

                    string localImagePath = await DownloadAndCacheImageAsync(url, safeFileName, gameId, forceRefresh);

                    int resultCount = string.IsNullOrEmpty(localImagePath) ? 0 : 1;
                    Debug.WriteLine($"[Scraper] Aranan: '{candidate}' -> Sonuç: {resultCount}");

                    if (resultCount > 0)
                    {
                        result.ArtworkPath = localImagePath;
                        if (result.Developer == "Bilinmiyor") result.Developer = "SEGA";
                        return;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Libretro boxart indirme hatası: {ex.Message}");
        }
    }

    private async Task TryFetchFromWikipediaAsync(string cleanTitle, GameMetadataResult result, bool forceRefresh, SystemType sysType)
    {
        try
        {
            var searchQueries = new List<string>
            {
                cleanTitle,
                $"{cleanTitle} Sega {sysType}"
            };

            var words = cleanTitle.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (words.Length > 2)
            {
                searchQueries.Add($"{words[0]} {words[1]}");
            }

            string? targetPageTitle = null;

            foreach (var query in searchQueries)
            {
                string searchUrl = $"https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch={Uri.EscapeDataString(query)}&utf8=&format=json";
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(4));
                var searchResponse = await HttpClient.GetAsync(searchUrl, cts.Token);

                if (searchResponse.IsSuccessStatusCode)
                {
                    using var doc = await JsonDocument.ParseAsync(await searchResponse.Content.ReadAsStreamAsync(cts.Token));
                    var root = doc.RootElement;

                    if (root.TryGetProperty("query", out var queryObj) && queryObj.TryGetProperty("search", out var searchArray))
                    {
                        int resultCount = searchArray.GetArrayLength();
                        Debug.WriteLine($"[Scraper] Aranan: '{query}' -> Sonuç: {resultCount}");

                        if (resultCount > 0)
                        {
                            // En alakalı ilk sonucun sayfa başlığını al
                            targetPageTitle = searchArray[0].GetProperty("title").GetString();
                            break; // Bulundu, döngüden çık
                        }
                    }
                }
            }

            if (!string.IsNullOrEmpty(targetPageTitle))
            {
                string summaryUrl = $"https://en.wikipedia.org/api/rest_v1/page/summary/{Uri.EscapeDataString(targetPageTitle)}";
                using var cts2 = new CancellationTokenSource(TimeSpan.FromSeconds(4));
                var summaryResponse = await HttpClient.GetAsync(summaryUrl, cts2.Token);

                if (summaryResponse.IsSuccessStatusCode)
                {
                    using var summaryDoc = await JsonDocument.ParseAsync(await summaryResponse.Content.ReadAsStreamAsync(cts2.Token));
                    var summaryRoot = summaryDoc.RootElement;

                    if (summaryRoot.TryGetProperty("extract", out var extractProp))
                    {
                        string extract = extractProp.GetString() ?? "";
                        if (!string.IsNullOrWhiteSpace(extract) && extract.Length > 20)
                        {
                            result.Summary = extract.Trim();

                            var match = System.Text.RegularExpressions.Regex.Match(extract, @"\b(198\d|199\d|200\d)\b");
                            if (match.Success)
                            {
                                result.ReleaseYear = match.Value;
                            }

                            if (extract.Contains("Sega", StringComparison.OrdinalIgnoreCase))
                            {
                                result.Developer = "SEGA";
                            }
                        }
                    }

                    if (string.IsNullOrEmpty(result.ArtworkPath) &&
                        summaryRoot.TryGetProperty("thumbnail", out var thumbProp) &&
                        thumbProp.TryGetProperty("source", out var srcProp))
                    {
                        string imgUrl = srcProp.GetString() ?? "";
                        if (!string.IsNullOrEmpty(imgUrl))
                        {
                            string safeFileName = string.Join("_", $"{cleanTitle}_{sysType}_Wiki".Split(Path.GetInvalidFileNameChars()));
                            string localImagePath = await DownloadAndCacheImageAsync(imgUrl, safeFileName, result.Title.Replace(" ", "_"), forceRefresh);
                            if (!string.IsNullOrEmpty(localImagePath))
                            {
                                result.ArtworkPath = localImagePath;
                            }
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Wikipedia çekme hatası: {ex.Message}");
        }
    }

    private async Task<string> DownloadAndCacheImageAsync(string imageUrl, string gameTitleFileName, string gameId, bool forceRefresh = false)
    {
        try
        {
            string ext = imageUrl.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase) || imageUrl.EndsWith(".jpeg", StringComparison.OrdinalIgnoreCase) ? ".jpg" : ".png";
            string titlePath = Path.Combine(_coversDirectory, $"{gameTitleFileName}{ext}");

            if (forceRefresh)
            {
                try
                {
                    string otherExt = ext == ".jpg" ? ".png" : ".jpg";
                    string otherPath = Path.Combine(_coversDirectory, $"{gameTitleFileName}{otherExt}");
                    if (File.Exists(titlePath)) File.Delete(titlePath);
                    if (File.Exists(otherPath)) File.Delete(otherPath);
                }
                catch { /* Ignored if locked */ }
            }
            else if (File.Exists(titlePath) && new FileInfo(titlePath).Length > 500)
            {
                return titlePath;
            }

            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(6));
            var response = await HttpClient.GetAsync(imageUrl, cts.Token);

            if (response.IsSuccessStatusCode)
            {
                byte[] imageBytes = await response.Content.ReadAsByteArrayAsync(cts.Token);
                if (imageBytes != null && imageBytes.Length > 500)
                {
                    await File.WriteAllBytesAsync(titlePath, imageBytes, cts.Token);
                    return titlePath;
                }
            }

            Debug.WriteLine($"Kapak indirilemedi: {imageUrl}");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Kapak indirilemedi: {imageUrl} — Hata: {ex.Message}");
            DiagnosticLog.WriteError("MetadataService", $"Görsel indirilemedi ({imageUrl}): {ex.Message}");
        }

        return string.Empty;
    }

    /// <summary>
    /// Kullanıcı tarafından seçilen yerel görsel dosyasını Data/Covers klasörüne kaydeder.
    /// </summary>
    public string SaveCustomCoverImage(string sourceFilePath, string gameId)
    {
        try
        {
            if (!File.Exists(sourceFilePath)) return string.Empty;

            string extension = Path.GetExtension(sourceFilePath);
            if (string.IsNullOrEmpty(extension)) extension = ".png";

            string targetFileName = $"{gameId}_{DateTime.Now.Ticks}{extension}";
            string targetPath = Path.Combine(_coversDirectory, targetFileName);

            File.Copy(sourceFilePath, targetPath, overwrite: true);
            return targetPath;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Özel kapak kaydetme hatası: {ex.Message}");
            DiagnosticLog.WriteError("MetadataService", $"Özel kapak resmi kopyalanamadı: {ex.Message}");
            return sourceFilePath; // Fallback: Orijinal dosya yolunu dön
        }
    }
}
