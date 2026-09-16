using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Platform.Storage;
using YDrive.Services;
using Android.Content;
using Android.App;

namespace YDrive.Android;

public class AndroidPlatformService : IPlatformService
{
    private readonly Context _context;

    public AndroidPlatformService(Context context)
    {
        _context = context;
    }

    private TopLevel? GetTopLevel()
    {
        try
        {
            if (Avalonia.Application.Current?.ApplicationLifetime is ISingleViewApplicationLifetime singleView && singleView.MainView != null)
            {
                var top = TopLevel.GetTopLevel(singleView.MainView);
                if (top != null) return top;
            }

            if (Avalonia.Application.Current?.ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop && desktop.MainWindow != null)
            {
                return desktop.MainWindow;
            }
        }
        catch (Exception ex)
        {
            global::Android.Util.Log.Error("YDrive", $"[Platform] GetTopLevel error: {ex.Message}");
        }
        return null;
    }

    public async Task<string?> OpenFileDialogAsync(string title, string filters)
    {
        try
        {
            var topLevel = GetTopLevel();
            if (topLevel == null)
            {
                global::Android.Util.Log.Warn("YDrive", "[Platform] TopLevel bulunamadı");
                return null;
            }

            var options = new FilePickerOpenOptions
            {
                Title = title,
                AllowMultiple = false,
                FileTypeFilter = CreateFileTypeFilters()
            };

            var files = await topLevel.StorageProvider.OpenFilePickerAsync(options);
            if (files == null || files.Count == 0) return null;

            return await CopyToLocalCacheAsync(files[0]);
        }
        catch (Exception ex)
        {
            global::Android.Util.Log.Error("YDrive", $"[Platform] OpenFileDialogAsync error: {ex.Message}");
            return null;
        }
    }

    public async Task<string[]> OpenMultipleFileDialogAsync(string title, string filters)
    {
        try
        {
            var topLevel = GetTopLevel();
            if (topLevel == null)
            {
                global::Android.Util.Log.Warn("YDrive", "[Platform] TopLevel bulunamadı");
                return Array.Empty<string>();
            }

            var options = new FilePickerOpenOptions
            {
                Title = title,
                AllowMultiple = true,
                FileTypeFilter = CreateFileTypeFilters()
            };

            var files = await topLevel.StorageProvider.OpenFilePickerAsync(options);
            if (files == null || files.Count == 0) return Array.Empty<string>();

            var results = new List<string>();
            foreach (var file in files)
            {
                var localPath = await CopyToLocalCacheAsync(file);
                if (!string.IsNullOrEmpty(localPath))
                {
                    results.Add(localPath);
                }
            }
            return results.ToArray();
        }
        catch (Exception ex)
        {
            global::Android.Util.Log.Error("YDrive", $"[Platform] OpenMultipleFileDialogAsync error: {ex.Message}");
            return Array.Empty<string>();
        }
    }

    private static List<FilePickerFileType> CreateFileTypeFilters()
    {
        return new List<FilePickerFileType>
        {
            new("SEGA & Retro ROMs (*.md, *.bin, *.gen, *.zip...)")
            {
                Patterns = new[] { "*.md", "*.gen", "*.bin", "*.smd", "*.sms", "*.gg", "*.32x", "*.iso", "*.cue", "*.chd", "*.zip", "*.7z" },
                MimeTypes = new[] { "application/octet-stream", "application/x-genesis-rom", "application/zip" }
            },
            FilePickerFileTypes.All
        };
    }

    /// <summary>
    /// Android SAF (Storage Access Framework) ile seçilen dosyayı
    /// uygulamanın Files/Roms dizinine güvenle kopyalar ve yerel dosya yolunu döndürür.
    /// </summary>
    private async Task<string?> CopyToLocalCacheAsync(IStorageFile file)
    {
        try
        {
            if (file == null) return null;

            // Güvenli yerel ROM hedef dizini (Cache/Roms veya Files/Roms)
            var appDir = _context.CacheDir?.AbsolutePath ?? _context.FilesDir?.AbsolutePath ?? GetAppDirectory();
            var romsDir = Path.Combine(appDir, "Roms");
            if (!Directory.Exists(romsDir))
            {
                Directory.CreateDirectory(romsDir);
            }

            // Dosya adını temizle ve belirle
            var fileName = file.Name;
            if (string.IsNullOrWhiteSpace(fileName))
            {
                fileName = $"rom_{Guid.NewGuid():N}.bin";
            }

            var destPath = Path.Combine(romsDir, fileName);
            string ext = Path.GetExtension(fileName).ToLowerInvariant();

            // ── Akıllı Cache: Büyük disk imajları için kopyalamayı atla ──
            // CHD/ISO dosyaları 300MB-1GB+ boyutunda olabilir.
            // Aynı dosya adı ve boyutu mevcutsa kopyalama yapmadan hazır yolu dön.
            // Bu hem açılış süresini hem de depolama tüketimini dramatik olarak azaltır.
            bool isDiscImage = ext == ".chd" || ext == ".iso" || ext == ".bin";

            if (isDiscImage && File.Exists(destPath))
            {
                try
                {
                    long existingSize = new FileInfo(destPath).Length;
                    // SAF üzerinden kaynak boyutunu al
                    long? sourceSize = null;
                    try
                    {
                        var props = await file.GetBasicPropertiesAsync();
                        sourceSize = (long?)props?.Size;
                    }
                    catch { }

                    if (sourceSize.HasValue && sourceSize.Value == existingSize && existingSize > 0)
                    {
                        global::Android.Util.Log.Info("YDrive",
                            $"[Cache] {ext.ToUpper()} zaten önbellekte ({existingSize / (1024 * 1024)} MB) → kopyalama atlandı: {fileName}");
                        return destPath;
                    }

                    global::Android.Util.Log.Info("YDrive",
                        $"[Cache] {ext.ToUpper()} boyutu değişmiş (mevcut={existingSize}, kaynak={sourceSize}) → yeniden kopyalanıyor");
                }
                catch (Exception cacheEx)
                {
                    global::Android.Util.Log.Warn("YDrive", $"[Cache] Boyut kontrolü başarısız: {cacheEx.Message} → kopyalama devam ediyor");
                }
            }

            // SAF Akışından yerel dosyaya kopyala

            await using var srcStream = await file.OpenReadAsync();
            await using var dstStream = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None);
            await srcStream.CopyToAsync(dstStream);
            await dstStream.FlushAsync();

            global::Android.Util.Log.Info("YDrive", $"[SAF] ROM kaydedildi: {fileName} -> {destPath}");

            // ── CUE dosyası için eşlik eden .bin / .iso track dosyalarını kopyala ──
            // CUE sheet, her data/ses parçasını ayrı .bin dosyası olarak listeler.
            // Bu dosyalar SAF kısıtlaması nedeniyle orijinal konumdan okunamaz;
            // .cue ile aynı dizine kopyalanmazsa çekirdek track'leri bulamaz → SIGSEGV.
            if (Path.GetExtension(fileName).Equals(".cue", StringComparison.OrdinalIgnoreCase))
            {
                await CopyCueCompanionFilesAsync(file, romsDir, destPath);
            }

            return destPath;
        }
        catch (Exception ex)
        {
            global::Android.Util.Log.Error("YDrive", $"[SAF] Dosya aktarım hatası: {ex.Message}");
            return null;
        }
    }

    public Task<string?> SaveFileDialogAsync(string title, string filters, string defaultExt)
    {
        return Task.FromResult<string?>(null);
    }

    /// <summary>
    /// .cue dosyasından referans edilen tüm track dosyalarını (.bin, .iso) yerel Roms dizinine kopyalar.
    /// CUE sheet format: FILE "track.bin" BINARY
    /// </summary>
    private async Task CopyCueCompanionFilesAsync(IStorageFile cueFile, string localRomsDir, string localCuePath)
    {
        try
        {
            // Kopyalanan .cue dosyasını oku ve FILE satırlarını parse et
            string cueText = await File.ReadAllTextAsync(localCuePath);
            var lines = cueText.Split('\n', StringSplitOptions.RemoveEmptyEntries);

            var referencedFiles = new System.Collections.Generic.List<string>();
            foreach (var line in lines)
            {
                string trimmed = line.Trim();
                // Format: FILE "filename.bin" BINARY  veya  FILE filename.bin BINARY
                if (trimmed.StartsWith("FILE", StringComparison.OrdinalIgnoreCase))
                {
                    string? trackName = null;
                    int q1 = trimmed.IndexOf('"');
                    int q2 = trimmed.LastIndexOf('"');
                    if (q1 >= 0 && q2 > q1)
                    {
                        trackName = trimmed.Substring(q1 + 1, q2 - q1 - 1);
                    }
                    else
                    {
                        // Tırnaksız format
                        var parts = trimmed.Split(' ', StringSplitOptions.RemoveEmptyEntries);
                        if (parts.Length >= 2) trackName = parts[1];
                    }

                    if (!string.IsNullOrEmpty(trackName))
                        referencedFiles.Add(trackName);
                }
            }

            if (referencedFiles.Count == 0)
            {
                global::Android.Util.Log.Warn("YDrive", "[CUE] Hiç track dosyası bulunamadı.");
                return;
            }

            global::Android.Util.Log.Info("YDrive", $"[CUE] {referencedFiles.Count} track dosyası referans edildi.");

            // CUE ile aynı klasördeki tüm dosyaları listele (SAF üzerinden)
            var cueParentFolder = await cueFile.GetParentAsync();
            if (cueParentFolder == null)
            {
                global::Android.Util.Log.Warn("YDrive", "[CUE] CUE dosyasının parent klasörüne erişilemedi. Track kopyalaması atlandı.");
                return;
            }

            await foreach (var item in cueParentFolder.GetItemsAsync())
            {
                if (item is not IStorageFile siblingFile) continue;

                string siblingName = siblingFile.Name;
                // Bu dosya CUE'da referans ediliyor mu?
                bool isReferenced = referencedFiles.Exists(rf =>
                    string.Equals(rf, siblingName, StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(Path.GetFileName(rf), siblingName, StringComparison.OrdinalIgnoreCase));

                if (!isReferenced) continue;

                string destTrackPath = Path.Combine(localRomsDir, siblingName);

                // Zaten kopyalanmışsa atla (aynı sürüm ise)
                if (File.Exists(destTrackPath))
                {
                    long existingSize = new FileInfo(destTrackPath).Length;
                    global::Android.Util.Log.Info("YDrive", $"[CUE] Track zaten mevcut ({existingSize} byte): {siblingName}");
                    continue;
                }

                try
                {
                    global::Android.Util.Log.Info("YDrive", $"[CUE] Track kopyalanıyor: {siblingName}");
                    await using var trackSrc = await siblingFile.OpenReadAsync();
                    await using var trackDst = new FileStream(destTrackPath, FileMode.Create, FileAccess.Write, FileShare.None);
                    await trackSrc.CopyToAsync(trackDst);
                    await trackDst.FlushAsync();
                    global::Android.Util.Log.Info("YDrive", $"[CUE] Track kopyalandı: {siblingName} -> {destTrackPath}");
                }
                catch (Exception trackEx)
                {
                    global::Android.Util.Log.Error("YDrive", $"[CUE] Track kopyalama hatası ({siblingName}): {trackEx.Message}");
                }
            }
        }
        catch (Exception ex)
        {
            global::Android.Util.Log.Error("YDrive", $"[CUE] CopyCueCompanionFilesAsync hatası: {ex.Message}");
        }
    }


    public Task ShowMessageAsync(string title, string message)
    {
        Application.SynchronizationContext?.Post(_ =>
        {
            try
            {
                global::Android.Widget.Toast.MakeText(_context, $"{title}: {message}", global::Android.Widget.ToastLength.Short)?.Show();
                global::Android.Util.Log.Info("YDrive", $"[MSG] {title}: {message}");
            }
            catch { }
        }, null);
        return Task.CompletedTask;
    }

    public Task<bool> ShowConfirmAsync(string title, string message, string positiveButton = "Evet", string negativeButton = "Hayır")
    {
        var tcs = new TaskCompletionSource<bool>();

        Application.SynchronizationContext?.Post(_ =>
        {
            try
            {
                var builder = new global::Android.App.AlertDialog.Builder(_context);
                builder.SetTitle(title);
                builder.SetMessage(message);
                builder.SetPositiveButton(positiveButton, (sender, args) => tcs.TrySetResult(true));
                
                if (!string.IsNullOrEmpty(negativeButton))
                {
                    builder.SetNegativeButton(negativeButton, (sender, args) => tcs.TrySetResult(false));
                }
                
                builder.SetCancelable(false);
                
                var dialog = builder.Show();
                
                // Set button colors to a more prominent bright blue (Material Blue A400)
                var prominentBlue = global::Android.Graphics.Color.ParseColor("#2979FF");
                var btnPositive = dialog.GetButton((int)global::Android.Content.DialogButtonType.Positive);
                btnPositive?.SetTextColor(prominentBlue);
                
                if (!string.IsNullOrEmpty(negativeButton))
                {
                    var btnNegative = dialog.GetButton((int)global::Android.Content.DialogButtonType.Negative);
                    btnNegative?.SetTextColor(prominentBlue);
                }
            }
            catch (Exception ex)
            {
                global::Android.Util.Log.Error("YDrive", $"[Dialog] Confirm dialog hatası: {ex.Message}");
                tcs.TrySetResult(false);
            }
        }, null);

        return tcs.Task;
    }

    public Stream? OpenAsset(string path)
    {
        try
        {
            return _context.Assets?.Open(path);
        }
        catch (Exception ex)
        {
            global::Android.Util.Log.Error("YDrive", $"[Asset] Açılamadı: {path} — {ex.Message}");
            return null;
        }
    }

    public string GetAppDirectory()
    {
        return _context.FilesDir?.AbsolutePath ?? string.Empty;
    }

    public string? GetNativeLibraryPath(string libName)
    {
        try
        {
            var nativeDir = _context.ApplicationInfo?.NativeLibraryDir;
            if (!string.IsNullOrEmpty(nativeDir) && Directory.Exists(nativeDir))
            {
                string[] candidates = {
                    $"lib{libName}.so",
                    $"{libName}.so",
                    libName,
                    "libgenesis_plus_gx_libretro_android.so",
                    "libgenesis_plus_gx_libretro.so"
                };

                foreach (var candidate in candidates)
                {
                    var fullPath = Path.Combine(nativeDir, candidate);
                    if (File.Exists(fullPath))
                    {
                        global::Android.Util.Log.Info("YDrive", $"[Platform] Yerel kütüphane bulundu: {fullPath}");
                        return fullPath;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            global::Android.Util.Log.Error("YDrive", $"[Platform] NativeLibraryDir hatası: {ex.Message}");
        }
        return null;
    }

    public async Task<bool> SaveImageToGalleryAsync(byte[] imageBytes, string fileName)
    {
        try
        {
            if (global::Android.OS.Build.VERSION.SdkInt >= global::Android.OS.BuildVersionCodes.Q)
            {
                var values = new ContentValues();
                values.Put(global::Android.Provider.MediaStore.IMediaColumns.DisplayName, fileName);
                values.Put(global::Android.Provider.MediaStore.IMediaColumns.MimeType, "image/png");
                values.Put(global::Android.Provider.MediaStore.IMediaColumns.RelativePath, global::Android.OS.Environment.DirectoryPictures + "/YDrive");
                values.Put(global::Android.Provider.MediaStore.IMediaColumns.IsPending, 1);

                var resolver = _context.ContentResolver;
                var uri = resolver?.Insert(global::Android.Provider.MediaStore.Images.Media.ExternalContentUri, values);
                if (uri != null && resolver != null)
                {
                    using (var stream = resolver.OpenOutputStream(uri))
                    {
                        if (stream != null)
                        {
                            await stream.WriteAsync(imageBytes, 0, imageBytes.Length);
                            await stream.FlushAsync();
                        }
                    }

                    values.Clear();
                    values.Put(global::Android.Provider.MediaStore.IMediaColumns.IsPending, 0);
                    resolver.Update(uri, values, null, null);
                    global::Android.Util.Log.Info("YDrive", $"[Screenshot] Galeriye kaydedildi (MediaStore): {fileName}");
                    return true;
                }
            }
            else
            {
                var picturesDir = global::Android.OS.Environment.GetExternalStoragePublicDirectory(global::Android.OS.Environment.DirectoryPictures);
                var ydriveDir = Path.Combine(picturesDir?.AbsolutePath ?? "", "YDrive");
                Directory.CreateDirectory(ydriveDir);
                var filePath = Path.Combine(ydriveDir, fileName);
                await File.WriteAllBytesAsync(filePath, imageBytes);

                global::Android.Media.MediaScannerConnection.ScanFile(_context, new[] { filePath }, new[] { "image/png" }, null);
                global::Android.Util.Log.Info("YDrive", $"[Screenshot] Galeriye kaydedildi (Legacy): {filePath}");
                return true;
            }
        }
        catch (Exception ex)
        {
            global::Android.Util.Log.Error("YDrive", $"[Screenshot] Galeriye kaydetme hatası: {ex.Message}");
        }
        return false;
    }

    public static IntPtr LoadLibretroCore(string soName)
    {
        try
        {
            var handle = System.Runtime.InteropServices.NativeLibrary.Load(soName);
            global::Android.Util.Log.Info("YDrive", $"[Core] Libretro çekirdeği yüklendi: {soName}");
            return handle;
        }
        catch (Exception ex)
        {
            global::Android.Util.Log.Error("YDrive", $"[Core] Libretro yükleme hatası ({soName}): {ex.Message}");
            return IntPtr.Zero;
        }
    }

    public async Task<bool> ExportFileToDownloadsAsync(string filePath, string newFileName)
    {
        try
        {
            if (!File.Exists(filePath)) return false;
            
            if (global::Android.OS.Build.VERSION.SdkInt >= global::Android.OS.BuildVersionCodes.Q)
            {
                var values = new ContentValues();
                values.Put(global::Android.Provider.MediaStore.IMediaColumns.DisplayName, newFileName);
                values.Put(global::Android.Provider.MediaStore.IMediaColumns.MimeType, "text/plain");
                values.Put(global::Android.Provider.MediaStore.IMediaColumns.RelativePath, global::Android.OS.Environment.DirectoryDownloads + "/YDrive");
                values.Put(global::Android.Provider.MediaStore.IMediaColumns.IsPending, 1);

                var resolver = _context.ContentResolver;
                var uri = resolver?.Insert(global::Android.Provider.MediaStore.Downloads.ExternalContentUri, values);
                if (uri != null && resolver != null)
                {
                    using (var outStream = resolver.OpenOutputStream(uri))
                    using (var inStream = File.OpenRead(filePath))
                    {
                        if (outStream != null)
                        {
                            await inStream.CopyToAsync(outStream);
                            await outStream.FlushAsync();
                        }
                    }

                    values.Clear();
                    values.Put(global::Android.Provider.MediaStore.IMediaColumns.IsPending, 0);
                    resolver.Update(uri, values, null, null);
                    global::Android.Util.Log.Info("YDrive", $"[Export] Log exported to Downloads/YDrive via MediaStore: {newFileName}");
                    return true;
                }
            }
            else
            {
                var downloadsDir = global::Android.OS.Environment.GetExternalStoragePublicDirectory(global::Android.OS.Environment.DirectoryDownloads);
                var ydriveDir = Path.Combine(downloadsDir?.AbsolutePath ?? "", "YDrive");
                Directory.CreateDirectory(ydriveDir);
                var destPath = Path.Combine(ydriveDir, newFileName);
                
                File.Copy(filePath, destPath, true);
                
                global::Android.Media.MediaScannerConnection.ScanFile(_context, new[] { destPath }, new[] { "text/plain" }, null);
                global::Android.Util.Log.Info("YDrive", $"[Export] Log exported to Downloads/YDrive via Legacy: {destPath}");
                return true;
            }
        }
        catch (Exception ex)
        {
            global::Android.Util.Log.Error("YDrive", $"[Export] Log export error: {ex.Message}");
        }
        return false;
    }
}
