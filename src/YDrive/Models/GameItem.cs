using System;

namespace SegaEmulator.Models;

/// <summary>
/// Sistem türleri.
/// </summary>
public enum SystemType
{
    Genesis,
    SegaCD,
    Sega32X,
    MasterSystem,
    GameGear,
    Unknown
}

/// <summary>
/// Oyun kütüphanesindeki tek bir oyunun veri modelini temsil eder.
/// </summary>
public class GameItem
{
    public SystemType SystemType { get; set; } = SystemType.Genesis;
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = string.Empty;
    public string RomPath { get; set; } = string.Empty;
    public string ConsoleName { get; set; } = "SEGA Genesis / Mega Drive";
    public string ReleaseYear { get; set; } = "Bilinmiyor";
    public string Developer { get; set; } = "Bilinmiyor";
    public string Summary { get; set; } = "Oyun özet bilgisi henüz çekilmedi.";
    public string ArtworkPath { get; set; } = string.Empty;

    // CoverImagePath takma adı (ArtworkPath ile senkronize)
    public string CoverImagePath
    {
        get => ArtworkPath;
        set => ArtworkPath = value;
    }

    public DateTime AddedDate { get; set; } = DateTime.Now;
    public DateTime? LastPlayedDate { get; set; }
}
