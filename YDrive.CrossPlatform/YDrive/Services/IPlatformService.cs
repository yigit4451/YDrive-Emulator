using System.Threading.Tasks;

namespace YDrive.Services;

public interface IPlatformService
{
    Task<string?> OpenFileDialogAsync(string title, string filter);
    Task<string[]> OpenMultipleFileDialogAsync(string title, string filter);
    Task ShowMessageAsync(string title, string message);
    Task<bool> ShowConfirmAsync(string title, string message, string positiveButton = "Evet", string negativeButton = "Hayır");
    string GetAppDirectory();
    string? GetNativeLibraryPath(string libName);
    Task<bool> SaveImageToGalleryAsync(byte[] imageBytes, string fileName);
    Task<bool> ExportFileToDownloadsAsync(string filePath, string newFileName);
}
