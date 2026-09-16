using System;
using System.Collections.Generic;

namespace SegaEmulator.Helpers;

public class KnownGameInfo
{
    public string ReleaseYear { get; set; } = "Bilinmiyor";
    public string Developer { get; set; } = "SEGA";
    public string Genre { get; set; } = "Aksiyon / Platform";
    public string Summary { get; set; } = string.Empty;
    public string SummaryEn { get; set; } = string.Empty;
}

/// <summary>
/// SEGA Genesis / Mega Drive efsanevi oyunları için bilinen yerel metadata veritabanı.
/// İnternet bağlantısı olmasa dahi doğru çıkış yılı, yapımcı ve özet sunar.
/// </summary>
public static class KnownGamesDatabase
{
    private static readonly Dictionary<string, KnownGameInfo> Database = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Sonic the Hedgehog"] = new KnownGameInfo
        {
            ReleaseYear = "1991",
            Developer = "Sonic Team / SEGA",
            Genre = "Platform",
            Summary = "Sonic the Hedgehog, Sonic Team tarafından geliştirilen ve SEGA tarafından 1991 yılında yayınlanan efsanevi platform oyunudur. Dr. Robotnik'in planlarını bozmak için hızlı kirpimiz Sonic dünyayı kurtarmaya koşuyor.",
            SummaryEn = "Sonic the Hedgehog is a legendary platform game developed by Sonic Team and published by SEGA in 1991. Our fast hedgehog Sonic rushes to save the world to thwart Dr. Robotnik's plans."
        },
        ["Sonic the Hedgehog 2"] = new KnownGameInfo
        {
            ReleaseYear = "1992",
            Developer = "Sonic Team / SEGA",
            Genre = "Platform",
            Summary = "Sonic'in yanına iki kuyruklu tilki Miles 'Tails' Prower ve Spin Dash yeteneğinin eklendiği, serinin en çok satan ve sevilen devam oyunu.",
            SummaryEn = "The best-selling and beloved sequel of the series, where the two-tailed fox Miles 'Tails' Prower and the Spin Dash ability are added alongside Sonic."
        },
        ["Sonic the Hedgehog 3"] = new KnownGameInfo
        {
            ReleaseYear = "1994",
            Developer = "Sonic Team / SEGA",
            Genre = "Platform",
            Summary = "Knuckles the Echidna karakterini ilk kez tanıtan, yenilenmiş grafikler ve muazzam müziklere sahip efsanevi 16-bit SEGA oyunu.",
            SummaryEn = "The legendary 16-bit SEGA game featuring revamped graphics and tremendous music, introducing the character Knuckles the Echidna for the first time."
        },
        ["Sonic & Knuckles"] = new KnownGameInfo
        {
            ReleaseYear = "1994",
            Developer = "Sonic Team / SEGA",
            Genre = "Platform",
            Summary = "Devrimsel Lock-On teknolojisine sahip kaset mimarisiyle Sonic 2 ve Sonic 3 oyunlarını birleştirip Knuckles ile oynama imkanı sunan klasik.",
            SummaryEn = "A classic that offers the opportunity to combine Sonic 2 and Sonic 3 games and play with Knuckles with its cartridge architecture featuring revolutionary Lock-On technology."
        },
        ["Sonic 3 & Knuckles"] = new KnownGameInfo
        {
            ReleaseYear = "1994",
            Developer = "Sonic Team / SEGA",
            Genre = "Platform",
            Summary = "Sonic 3 ve Sonic & Knuckles oyunlarının Lock-On teknolojisiyle birleştiği, serinin en efsanevi ve eksiksiz macerası.",
            SummaryEn = "The most legendary and complete adventure of the series, where Sonic 3 and Sonic & Knuckles are combined with Lock-On technology."
        },
        ["Sonic & Knuckles + Sonic The Hedgehog 3"] = new KnownGameInfo
        {
            ReleaseYear = "1994",
            Developer = "Sonic Team / SEGA",
            Genre = "Platform",
            Summary = "Sonic 3 ve Sonic & Knuckles oyunlarının Lock-On teknolojisiyle birleştiği, serinin en efsanevi ve eksiksiz macerası.",
            SummaryEn = "The most legendary and complete adventure of the series, where Sonic 3 and Sonic & Knuckles are combined with Lock-On technology."
        },
        ["Streets of Rage"] = new KnownGameInfo
        {
            ReleaseYear = "1991",
            Developer = "SEGA / MNM Software",
            Genre = "Beat 'em up",
            Summary = "Axel, Blaze ve Adam'ın suç örgütü lideri Mr. X'e karşı sokaklardaki amansız mücadelesini konu alan efsanevi dövüş oyunu.",
            SummaryEn = "The legendary beat 'em up game about Axel, Blaze, and Adam's relentless struggle in the streets against crime syndicate leader Mr. X."
        },
        ["Streets of Rage 2"] = new KnownGameInfo
        {
            ReleaseYear = "1992",
            Developer = "SEGA / Ancient",
            Genre = "Beat 'em up",
            Summary = "Yuzo Koshiro'nun efsanevi müzikleri, müthiş komboları ve Skate ile Max gibi yeni karakterleriyle 16-bit döneminin en iyi beat 'em up oyunu.",
            SummaryEn = "The best beat 'em up game of the 16-bit era with Yuzo Koshiro's legendary music, awesome combos, and new characters like Skate and Max."
        },
        ["Streets of Rage 3"] = new KnownGameInfo
        {
            ReleaseYear = "1994",
            Developer = "SEGA",
            Genre = "Beat 'em up",
            Summary = "Hızlı oynanış, gizli karakterler ve alternatif sonlarıyla Streets of Rage üçlemesinin son halkası.",
            SummaryEn = "The final installment of the Streets of Rage trilogy with fast gameplay, secret characters, and alternative endings."
        },
        ["Shinobi III: Return of the Ninja Master"] = new KnownGameInfo
        {
            ReleaseYear = "1993",
            Developer = "SEGA Megasoft",
            Genre = "Aksiyon / Ninja",
            Summary = "Master Joe Musashi'nin Neo Zeed örgütünü yok etmek için atletik ninja hareketleri ve ninjutsu büyülerini kullandığı başyapıt.",
            SummaryEn = "A masterpiece where Master Joe Musashi uses athletic ninja moves and ninjutsu magic to destroy the Neo Zeed organization."
        },
        ["The Revenge of Shinobi"] = new KnownGameInfo
        {
            ReleaseYear = "1989",
            Developer = "SEGA",
            Genre = "Aksiyon / Ninja",
            Summary = "SEGA Genesis kütüphanesinin en erken klasiklerinden biri. Yuzo Koshiro müzikleri ve ikonik boss dövüşleri içerir.",
            SummaryEn = "One of the earliest classics of the SEGA Genesis library. Features Yuzo Koshiro music and iconic boss fights."
        },
        ["Golden Axe"] = new KnownGameInfo
        {
            ReleaseYear = "1989",
            Developer = "SEGA",
            Genre = "Hack and Slash",
            Summary = "Ax Battler, Tyris Flare ve Gilius Thunderhead'in zalim Death Adder'a karşı ejderha sırtındaki fantastik mücadelesi.",
            SummaryEn = "The fantastic struggle of Ax Battler, Tyris Flare, and Gilius Thunderhead against the cruel Death Adder on dragonback."
        },
        ["Golden Axe II"] = new KnownGameInfo
        {
            ReleaseYear = "1991",
            Developer = "SEGA",
            Genre = "Hack and Slash",
            Summary = "Karanlık lonca lordu Dark Guld'a karşı yeni büyüler ve düşmanlarla geliştirilmiş fantastik dövüş macerası.",
            SummaryEn = "An enhanced fantastic fighting adventure with new spells and enemies against the dark guild lord Dark Guld."
        },
        ["Mortal Kombat"] = new KnownGameInfo
        {
            ReleaseYear = "1992",
            Developer = "Midway / Probe Entertainment",
            Genre = "Dövüş",
            Summary = "Ikonik Fatality hareketleri ve kan şifresi (ABACABB) ile SEGA Genesis kütüphanesini sallayan tarihi dövüş oyunu.",
            SummaryEn = "The historic fighting game that rocked the SEGA Genesis library with iconic Fatality moves and the blood code (ABACABB)."
        },
        ["Mortal Kombat II"] = new KnownGameInfo
        {
            ReleaseYear = "1993",
            Developer = "Midway / Probe Entertainment",
            Genre = "Dövüş",
            Summary = "Outworld turnuvası, Babality ve Friendship hareketleriyle dövüş oyunları tarihinin en prestijli yapımlarından biri.",
            SummaryEn = "One of the most prestigious productions in the history of fighting games with the Outworld tournament, Babality, and Friendship moves."
        },
        ["Mortal Kombat 3"] = new KnownGameInfo
        {
            ReleaseYear = "1995",
            Developer = "Midway / Williams",
            Genre = "Dövüş",
            Summary = "Shao Kahn'ın Dünya'yı istilası, kombo sistemi ve koşma (Run) mekaniğinin eklendiği yüksek tempolu dövüş.",
            SummaryEn = "High-paced combat featuring Shao Kahn's invasion of Earth, the addition of a combo system, and a run mechanic."
        },
        ["Ultimate Mortal Kombat 3"] = new KnownGameInfo
        {
            ReleaseYear = "1996",
            Developer = "Midway",
            Genre = "Dövüş",
            Summary = "Scorpion, Reptile ve Ermac gibi klasik ninjaların geri döndüğü kapsamlı dövüş sürümü.",
            SummaryEn = "A comprehensive fighting edition where classic ninjas like Scorpion, Reptile, and Ermac return."
        },
        ["Aladdin"] = new KnownGameInfo
        {
            ReleaseYear = "1993",
            Developer = "Virgin Games / Disney",
            Genre = "Platform",
            Summary = "Disney animatörlerinin el çizimi kareleriyle geliştirilen, kılıç dövüşü ve akrobatik oynanışıyla Oscar ödüllü görsel şölen.",
            SummaryEn = "An Oscar-winning visual feast developed with hand-drawn frames by Disney animators, featuring sword fighting and acrobatic gameplay."
        },
        ["The Lion King"] = new KnownGameInfo
        {
            ReleaseYear = "1994",
            Developer = "Virgin Games / Westwood Studios",
            Genre = "Platform",
            Summary = "Simba'nın yavru halinden yetişkin bir aslan kral olmasına giden zorlu ama muhteşem Afrika macerası.",
            SummaryEn = "The challenging but magnificent African adventure of Simba going from a cub to an adult lion king."
        },
        ["Earthworm Jim"] = new KnownGameInfo
        {
            ReleaseYear = "1994",
            Developer = "Shiny Entertainment",
            Genre = "Aksiyon / Platform",
            Summary = "Uzay giysisi giymiş solucan Jim'in mizah dolu, çılgın silahları ve olağanüstü animasyonlarıyla dolu kült oyunu.",
            SummaryEn = "The cult game full of humor, crazy weapons, and extraordinary animations of the spacesuit-wearing worm Jim."
        },
        ["Comix Zone"] = new KnownGameInfo
        {
            ReleaseYear = "1995",
            Developer = "SEGA Technical Institute",
            Genre = "Aksiyon / Beat 'em up",
            Summary = "Çizgi roman çizeri Sketch Turner'ın kendi çizgi roman karelerinin içine hapsolup kâğıt sayfalar üzerinde dövüştüğü şaheser.",
            SummaryEn = "A masterpiece where comic book artist Sketch Turner is trapped inside his own comic book panels and fights on paper pages."
        },
        ["Gunstar Heroes"] = new KnownGameInfo
        {
            ReleaseYear = "1993",
            Developer = "Treasure / SEGA",
            Genre = "Run and Gun",
            Summary = "Treasure stüdyosunun ilk yapıtı. Patlamalar, birleştirilebilir silah kombinasyonları ve çılgın boss savaşlarıyla temponun hiç düşmediği klasik.",
            SummaryEn = "Treasure studio's first work. A classic where the pace never drops with explosions, combinable weapon combinations, and crazy boss battles."
        },
        ["Phantasy Star IV"] = new KnownGameInfo
        {
            ReleaseYear = "1993",
            Developer = "SEGA",
            Genre = "RPG",
            Summary = "Manga tarzı ara sahneleri, büyü komboları ve büyüleyici hikayesiyle 16-bit JRPG döneminin zirve noktası.",
            SummaryEn = "The pinnacle of the 16-bit JRPG era with manga-style cutscenes, magic combos, and an enchanting story."
        },
        ["Castlevania: Bloodlines"] = new KnownGameInfo
        {
            ReleaseYear = "1994",
            Developer = "Konami",
            Genre = "Aksiyon / Platform",
            Summary = "John Morris ve Eric Lecarde'ın Kontes Elizabeth Bartley ve Drakula'ya karşı Avrupa genelindeki kanlı mücadelesi.",
            SummaryEn = "The bloody struggle of John Morris and Eric Lecarde across Europe against Countess Elizabeth Bartley and Dracula."
        },
        ["Contra: Hard Corps"] = new KnownGameInfo
        {
            ReleaseYear = "1994",
            Developer = "Konami",
            Genre = "Run and Gun",
            Summary = "4 seçilebilir karakter, dallanan hikaye rotaları ve inanılmaz zorluk seviyesiyle efsanevi Konami klasiği.",
            SummaryEn = "A legendary Konami classic with 4 selectable characters, branching story routes, and an incredible difficulty level."
        },
        ["VectorMan"] = new KnownGameInfo
        {
            ReleaseYear = "1995",
            Developer = "BlueSky Software / SEGA",
            Genre = "Platform",
            Summary = "Pre-rendered 3D görselleri, şekil değiştirebilen kahramanı VectorMan ve mükemmel müzikleriyle SEGA'nın teknik harikası.",
            SummaryEn = "SEGA's technical marvel with pre-rendered 3D visuals, shape-shifting hero VectorMan, and excellent music."
        },
        ["Ristar"] = new KnownGameInfo
        {
            ReleaseYear = "1995",
            Developer = "Sonic Team / SEGA",
            Genre = "Platform",
            Summary = "Uzayan kollarıyla düşmanları yakalayıp kafa atan sevimli uzay yıldızı Ristar'ın rengarenk gezegen macerası.",
            SummaryEn = "The colorful planetary adventure of the cute space star Ristar, who catches enemies with his extending arms and headbutts them."
        },
        ["Ecco the Dolphin"] = new KnownGameInfo
        {
            ReleaseYear = "1992",
            Developer = "Novotrade / SEGA",
            Genre = "Aksiyon / Macera",
            Summary = "Okyanusun derinliklerinde kaybolan sürüsünü arayan yunusun gizemli ve atmosferik su altı yolculuğu.",
            SummaryEn = "The mysterious and atmospheric underwater journey of a dolphin searching for his pod lost in the depths of the ocean."
        }
    };

    public static KnownGameInfo? GetInfo(string gameTitle)
    {
        if (string.IsNullOrWhiteSpace(gameTitle)) return null;

        // Birebir eşleşme dene
        if (Database.TryGetValue(gameTitle.Trim(), out var info))
        {
            return info;
        }

        KnownGameInfo? bestMatch = null;
        int maxMatchLength = -1;

        // Kısmi eşleşme dene (Örn: "Sonic 2" -> "Sonic the Hedgehog 2")
        // En uzun eşleşmeyi bularak, "Sonic The Hedgehog 3" yerine "Sonic 3 & Knuckles" eşleşmesini garanti altına alır.
        foreach (var kvp in Database)
        {
            if (gameTitle.Contains(kvp.Key, StringComparison.OrdinalIgnoreCase) ||
                kvp.Key.Contains(gameTitle, StringComparison.OrdinalIgnoreCase))
            {
                if (kvp.Key.Length > maxMatchLength)
                {
                    maxMatchLength = kvp.Key.Length;
                    bestMatch = kvp.Value;
                }
            }
        }

        return bestMatch;
    }
}
