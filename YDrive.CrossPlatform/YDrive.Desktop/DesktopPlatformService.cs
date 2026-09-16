using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using YDrive.Services;

namespace YDrive.Desktop;

public class DesktopPlatformService : IPlatformService
{
    private TopLevel? GetTopLevel()
    {
        if (Avalonia.Application.Current?.ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            return desktop.MainWindow;
        }
        return null;
    }

    public async Task<string?> OpenFileDialogAsync(string title, string filters)
    {
        var topLevel = GetTopLevel();
        if (topLevel == null) return null;

        var files = await topLevel.StorageProvider.OpenFilePickerAsync(new Avalonia.Platform.Storage.FilePickerOpenOptions
        {
            Title = title,
            AllowMultiple = false
        });

        return files.Count > 0 ? files[0].Path.LocalPath : null;
    }

    public async Task<string[]> OpenMultipleFileDialogAsync(string title, string filters)
    {
        var topLevel = GetTopLevel();
        if (topLevel == null) return Array.Empty<string>();

        var files = await topLevel.StorageProvider.OpenFilePickerAsync(new Avalonia.Platform.Storage.FilePickerOpenOptions
        {
            Title = title,
            AllowMultiple = true
        });

        var paths = new string[files.Count];
        for (int i = 0; i < files.Count; i++) paths[i] = files[i].Path.LocalPath;
        return paths;
    }

    public async Task<string?> SaveFileDialogAsync(string title, string filters, string defaultExt)
    {
        var topLevel = GetTopLevel();
        if (topLevel == null) return null;

        var file = await topLevel.StorageProvider.SaveFilePickerAsync(new Avalonia.Platform.Storage.FilePickerSaveOptions
        {
            Title = title,
            DefaultExtension = defaultExt
        });

        return file?.Path.LocalPath;
    }

    public async Task ShowMessageAsync(string title, string message)
    {
        Console.WriteLine($"[MESSAGE BOX] {title}: {message}");
        await Task.CompletedTask;
    }

    public Task<bool> ShowConfirmAsync(string title, string message, string positiveButton = "Evet", string negativeButton = "Hayır")
    {
        // Desktop: For now returns true to simulate confirmation (can be replaced with a custom dialog)
        Console.WriteLine($"[CONFIRM] {title}: {message}");
        return Task.FromResult(true);
    }

    public Stream? OpenAsset(string path)
    {
        // Desktop uses standard file paths if not embedded
        var fullPath = Path.Combine(AppContext.BaseDirectory, path);
        if (File.Exists(fullPath))
            return File.OpenRead(fullPath);
        return null;
    }

    public string GetAppDirectory()
    {
        return AppDomain.CurrentDomain.BaseDirectory;
    }

    public string? GetNativeLibraryPath(string libName) => null;

    public async Task<bool> SaveImageToGalleryAsync(byte[] imageBytes, string fileName)
    {
        try
        {
            var picturesDir = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
            var ydriveDir = Path.Combine(picturesDir, "YDrive");
            Directory.CreateDirectory(ydriveDir);
            var filePath = Path.Combine(ydriveDir, fileName);
            await File.WriteAllBytesAsync(filePath, imageBytes);
            Console.WriteLine($"[Screenshot] Kaydedildi: {filePath}");
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Screenshot] Hata: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> ExportFileToDownloadsAsync(string filePath, string newFileName)
    {
        try
        {
            if (!File.Exists(filePath)) return false;

            var desktopDir = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
            var ydriveDir = Path.Combine(desktopDir, "YDrive_Logs");
            Directory.CreateDirectory(ydriveDir);
            var destPath = Path.Combine(ydriveDir, newFileName);
            
            File.Copy(filePath, destPath, true);
            Console.WriteLine($"[Export] Log masaüstüne aktarıldı: {destPath}");
            return await Task.FromResult(true);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Export] Log aktarım hatası: {ex.Message}");
            return await Task.FromResult(false);
        }
    }
}
