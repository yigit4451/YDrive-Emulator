using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace YDrive.Services;

/// <summary>
/// Detects SEGA CD BIOS region by inspecting binary content (header bytes & MD5 hash).
/// File names are completely ignored.
/// </summary>
public static class BiosService
{
    public enum BiosRegion
    {
        Unknown,
        US,   // NTSC-U -> bios_CD_U.bin
        EU,   // PAL    -> bios_CD_E.bin
        JP    // NTSC-J -> bios_CD_J.bin
    }

    // Known SEGA CD BIOS MD5 hashes mapped to regions
    private static readonly Dictionary<string, BiosRegion> KnownHashes = new(StringComparer.OrdinalIgnoreCase)
    {
        // US BIOS variants
        { "2efd74e3232ff264e3042e5339597c29", BiosRegion.US },
        { "854b9150240a198074c5716bb2b45880", BiosRegion.US },
        { "e66fa1dc5820d254611fd9e107da504e", BiosRegion.US },
        // EU BIOS variants
        { "e2298711e6804f5e7178c18c1b268573", BiosRegion.EU },
        { "2e49d2c03eb73e653d35d110ac1fdd14", BiosRegion.EU },
        // JP BIOS variants
        { "278a9397e1421490f0aa7d94943f2f0a", BiosRegion.JP },
        { "9d2da8f219b1b706f9d2a6a5d4e16d3f", BiosRegion.JP },
        { "bdeb4c47da613315afbab03b14b977b0", BiosRegion.JP },
    };

    /// <summary>
    /// Returns the standard output file name for a given region.
    /// </summary>
    public static string GetFileName(BiosRegion region) => region switch
    {
        BiosRegion.US => "bios_CD_U.bin",
        BiosRegion.EU => "bios_CD_E.bin",
        BiosRegion.JP => "bios_CD_J.bin",
        _ => ""
    };

    /// <summary>
    /// Detects the BIOS region from raw file bytes.
    /// Strategy:
    ///   1) Validate size (128KB or 256KB)
    ///   2) Check header at 0x100 for "SEGA" magic
    ///   3) Read region byte at offset 0x01F0 and header string at 0x100-0x1FF
    ///   4) Fall back to MD5 hash lookup against known BIOS images
    /// </summary>
    public static BiosRegion DetectRegion(byte[] data)
    {
        if (data == null || data.Length == 0)
            return BiosRegion.Unknown;

        // Step 1: Size check — valid Sega CD BIOS is exactly 128KB or 256KB
        if (data.Length != 131072 && data.Length != 262144)
        {
            Console.WriteLine($"[BIOS] Invalid size: {data.Length} bytes. Aborting detection.");
            return BiosRegion.Unknown;
        }
        if (data.Length >= 0x200)
        {
            // Check for "SEGA" magic at 0x100
            bool hasMagic = false;
            try
            {
                string magic = Encoding.ASCII.GetString(data, 0x100, 16);
                hasMagic = magic.Contains("SEGA", StringComparison.OrdinalIgnoreCase);
            }
            catch { }

            if (hasMagic)
            {
                // Read region indicator byte at 0x01F0
                byte regionByte = data[0x01F0];
                switch ((char)regionByte)
                {
                    case 'U': case 'u': case 'A': case 'a': // America
                        return BiosRegion.US;
                    case 'E': case 'e':                       // Europe
                        return BiosRegion.EU;
                    case 'J': case 'j':                       // Japan
                        return BiosRegion.JP;
                }

                // Fallback: scan header string area 0x100 - 0x1FF for region keywords
                try
                {
                    string headerStr = Encoding.ASCII.GetString(data, 0x100, 0x100);
                    string headerUpper = headerStr.ToUpperInvariant();

                    if (headerUpper.Contains("USA") || headerUpper.Contains("AMERICA") || headerUpper.Contains("NTSC-U"))
                        return BiosRegion.US;
                    if (headerUpper.Contains("EUROPE") || headerUpper.Contains("PAL"))
                        return BiosRegion.EU;
                    if (headerUpper.Contains("JAPAN") || headerUpper.Contains("NTSC-J"))
                        return BiosRegion.JP;
                }
                catch { }
            }
        }

        // Step 3: MD5 hash fallback
        try
        {
            string md5 = ComputeMd5(data);
            Console.WriteLine($"[BIOS] MD5 = {md5}");
            if (KnownHashes.TryGetValue(md5, out var hashRegion))
                return hashRegion;
        }
        catch { }

        // If valid size and has SEGA magic but region unknown, still unknown
        return BiosRegion.Unknown;
    }

    /// <summary>
    /// Detect region from a file path on disk.
    /// </summary>
    public static BiosRegion DetectRegionFromFile(string filePath)
    {
        try
        {
            if (!File.Exists(filePath)) return BiosRegion.Unknown;
            byte[] data = File.ReadAllBytes(filePath);
            return DetectRegion(data);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[BIOS] DetectRegionFromFile error: {ex.Message}");
            return BiosRegion.Unknown;
        }
    }

    /// <summary>
    /// Reads a file, detects its region, and copies it to the target directory
    /// with the correct standard names for both Genesis Plus GX and Picodrive.
    /// </summary>
    public static BiosRegion InstallBios(string sourceFilePath, string systemDirectory)
    {
        try
        {
            if (!File.Exists(sourceFilePath))
            {
                Console.WriteLine($"[BIOS] Source file not found: {sourceFilePath}");
                return BiosRegion.Unknown;
            }

            byte[] data = File.ReadAllBytes(sourceFilePath);
            var region = DetectRegion(data);

            if (region == BiosRegion.Unknown)
            {
                Console.WriteLine($"[BIOS] Could not detect region for: {sourceFilePath}");
                return BiosRegion.Unknown;
            }

            // Ensure directory exists
            if (!Directory.Exists(systemDirectory))
                Directory.CreateDirectory(systemDirectory);

            // Genesis Plus GX name
            string genPlusName = GetFileName(region);
            string genPlusPath = Path.Combine(systemDirectory, genPlusName);
            File.WriteAllBytes(genPlusPath, data);

            // PicoDrive names
            string picoName = region switch
            {
                BiosRegion.US => "us_scd1_9210.bin",
                BiosRegion.EU => "eu_mcd1_9210.bin",
                BiosRegion.JP => "jp_mcd1_9112.bin",
                _ => ""
            };
            if (!string.IsNullOrEmpty(picoName))
            {
                string picoPath = Path.Combine(systemDirectory, picoName);
                File.WriteAllBytes(picoPath, data);
            }

            Console.WriteLine($"[BIOS] Installed {region} BIOS -> {genPlusPath} & {picoName}");
            return region;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[BIOS] InstallBios error: {ex.Message}");
            return BiosRegion.Unknown;
        }
    }

    public static void FillMissingBiosFiles(string systemDirectory)
    {
        try
        {
            if (!Directory.Exists(systemDirectory)) return;

            string[] genPlusNames = { "bios_CD_U.bin", "bios_CD_E.bin", "bios_CD_J.bin" };
            string[] picoNames = { "us_scd1_9210.bin", "eu_mcd1_9210.bin", "jp_mcd1_9112.bin" };

            // Find at least one valid BIOS file to use as a source
            string? sourceFile = null;
            byte[]? sourceData = null;

            foreach (var name in genPlusNames.Concat(picoNames))
            {
                string path = Path.Combine(systemDirectory, name);
                if (File.Exists(path))
                {
                    byte[] data = File.ReadAllBytes(path);
                    if (DetectRegion(data) != BiosRegion.Unknown)
                    {
                        sourceFile = path;
                        sourceData = data;
                        break; // found a valid source
                    }
                }
            }

            if (sourceData == null) return; // No valid BIOS found, can't fill

            // Fill missing for Genesis Plus GX
            foreach (var name in genPlusNames)
            {
                string path = Path.Combine(systemDirectory, name);
                if (!File.Exists(path))
                {
                    File.WriteAllBytes(path, sourceData);
                    Console.WriteLine($"[BIOS] Filled missing {name} with duplicate.");
                }
            }

            // Fill missing for PicoDrive
            foreach (var name in picoNames)
            {
                string path = Path.Combine(systemDirectory, name);
                if (!File.Exists(path))
                {
                    File.WriteAllBytes(path, sourceData);
                    Console.WriteLine($"[BIOS] Filled missing {name} with duplicate.");
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[BIOS] FillMissingBiosFiles error: {ex.Message}");
        }
    }

    private static string ComputeMd5(byte[] data)
    {
        using var md5 = MD5.Create();
        byte[] hash = md5.ComputeHash(data);
        var sb = new StringBuilder(hash.Length * 2);
        foreach (byte b in hash)
            sb.Append(b.ToString("x2"));
        return sb.ToString();
    }
}
