using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using YDrive.Models;

namespace YDrive.Services;

/// <summary>
/// Oyun kütüphanesini JSON dosyasında saklayan ve yöneten servis.
/// </summary>
public class GameLibraryService
{
    private readonly string _libraryFilePath;

    public GameLibraryService()
    {
        try
        {
            string appDataFolder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "YDrive");

            if (!Directory.Exists(appDataFolder))
            {
                Directory.CreateDirectory(appDataFolder);
            }
            _libraryFilePath = Path.Combine(appDataFolder, "library.json");
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[GameLibraryService] Init error: {ex.Message}");
            _libraryFilePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "library.json");
        }
    }

    public List<GameItem> LoadGames()
    {
        try
        {
            if (File.Exists(_libraryFilePath))
            {
                string json = File.ReadAllText(_libraryFilePath);
                if (!string.IsNullOrWhiteSpace(json))
                {
                    var games = JsonSerializer.Deserialize<List<GameItem>>(json);
                    if (games != null && games.Count > 0)
                    {
                        var validGames = games.Where(g => g != null).ToList();
                        if (validGames.Count > 0) return validGames;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[LibraryService] Kütüphane yüklenirken hata: {ex.Message}");
        }

        // Varsayılan olarak boş kütüphane döndür
        return new List<GameItem>();
    }

    public void SaveGames(IEnumerable<GameItem> games)
    {
        try
        {
            var options = new JsonSerializerOptions { WriteIndented = true };
            string json = JsonSerializer.Serialize(games, options);
            File.WriteAllText(_libraryFilePath, json);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[LibraryService] Kütüphane kaydedilirken hata: {ex.Message}");
        }
    }
}
