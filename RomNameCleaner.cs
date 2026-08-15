using System.IO;
using System.Text.RegularExpressions;

namespace SegaEmulator.Helpers;

/// <summary>
/// ROM dosya isimlerinden bölge, versiyon ve dump parantez içi etiketleri temizleme yardımcısı.
/// </summary>
public static class RomNameCleaner
{
    private static readonly Regex BracketPattern = new Regex(@"\s*[\(\[][^\)\]]*[\)\]]", RegexOptions.Compiled);
    private static readonly Regex ExtraSpacesPattern = new Regex(@"\s+", RegexOptions.Compiled);

    /// <summary>
    /// ROM dosya adından parantez içi etiketleri ve uzantıyı temizler.
    /// Örn: "Sonic the Hedgehog (USA, Europe) [!].bin" -> "Sonic the Hedgehog"
    /// </summary>
    public static string CleanTitle(string filePathOrName)
    {
        if (string.IsNullOrWhiteSpace(filePathOrName)) return string.Empty;

        string name = Path.GetFileNameWithoutExtension(filePathOrName);

        // Parantez içi (USA, Europe), [!], (E), (U) vb. etiketleri temizle
        name = BracketPattern.Replace(name, string.Empty);

        // Çift boşlukları ve kenar boşluklarını temizle
        name = ExtraSpacesPattern.Replace(name, " ").Trim();

        return string.IsNullOrWhiteSpace(name) ? Path.GetFileNameWithoutExtension(filePathOrName) : name;
    }
}
