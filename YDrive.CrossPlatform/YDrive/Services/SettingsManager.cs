using System;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using YDrive.Models;

namespace YDrive.Services;

public class SettingsManager
{
    private static string GetSettingsPath()
    {
        try
        {
            var dir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir))
            {
                dir = AppDomain.CurrentDomain.BaseDirectory;
            }
            if (string.IsNullOrEmpty(dir))
            {
                dir = Path.GetTempPath();
            }
            return Path.Combine(dir, "ydrive_settings.json");
        }
        catch
        {
            return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ydrive_settings.json");
        }
    }

    // Singleton instance
    private static SettingsManager? _instance;
    public static SettingsManager Instance => _instance ??= new SettingsManager();

    public AppSettings Current { get; private set; }

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
            string path = GetSettingsPath();
            if (File.Exists(path))
            {
                string json = File.ReadAllText(path);
                var settings = JsonSerializer.Deserialize<AppSettings>(json);
                if (settings != null)
                {
                    if (settings.TouchLayoutVersion < TouchLayoutService.CurrentLayoutVersion)
                    {
                        // Eski veya uyumsuz koordinatları geçersiz kıl, varsayılan düzene sıfırla
                        settings.IsCustomPositioned = false;
                        settings.TouchLayoutVersion = TouchLayoutService.CurrentLayoutVersion;
                        settings.TouchDPadX = 0;
                        settings.TouchDPadY = 0;
                        settings.TouchAX = 0;
                        settings.TouchAY = 0;
                        settings.TouchBX = 0;
                        settings.TouchBY = 0;
                        settings.TouchCX = 0;
                        settings.TouchCY = 0;
                        settings.TouchXX = 0;
                        settings.TouchXY = 0;
                        settings.TouchYX = 0;
                        settings.TouchYY = 0;
                        settings.TouchZX = 0;
                        settings.TouchZY = 0;
                        settings.TouchStartX = 0;
                        settings.TouchStartY = 0;
                    }
                    Current = settings;
                    Debug.WriteLine($"[SettingsManager] Ayarlar yüklendi: {path}");
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[SettingsManager] Yükleme hatası: {ex.Message}");
        }
    }

    public void SaveSettings()
    {
        try
        {
            string path = GetSettingsPath();
            string? dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }

            string json = JsonSerializer.Serialize(Current, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(path, json);
            Debug.WriteLine($"[SettingsManager] Ayarlar kaydedildi: {path}");
            
            SettingsChanged?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[SettingsManager] Kaydetme hatası: {ex.Message}");
        }
    }
}
