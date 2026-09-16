using System;
using System.IO;
using System.Text.Json;
using SegaEmulator.Models;

namespace SegaEmulator.Services;

public class SettingsManager
{
    private static readonly string SettingsFilePath = Path.Combine(Path.GetDirectoryName(Environment.ProcessPath) ?? AppDomain.CurrentDomain.BaseDirectory, "appsettings.json");

    // Singleton instance
    private static SettingsManager? _instance;
    public static SettingsManager Instance => _instance ??= new SettingsManager();

    public AppSettings Current { get; private set; }

    // Olay (Event) to notify view models when settings change
    public event EventHandler? SettingsChanged;

    private SettingsManager()
    {
        Current = new AppSettings();
        LoadSettings();
    }

    public void LoadSettings()
    {
        try
        {
            if (File.Exists(SettingsFilePath))
            {
                string json = File.ReadAllText(SettingsFilePath);
                var settings = JsonSerializer.Deserialize<AppSettings>(json);
                if (settings != null)
                {
                    Current = settings;
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[SettingsManager] Yükleme hatası: {ex.Message}");
            Current = new AppSettings();
        }
    }

    public void SaveSettings()
    {
        try
        {
            string json = JsonSerializer.Serialize(Current, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(SettingsFilePath, json);
            
            // Notify subscribers
            SettingsChanged?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[SettingsManager] Kaydetme hatası: {ex.Message}");
        }
    }
}
