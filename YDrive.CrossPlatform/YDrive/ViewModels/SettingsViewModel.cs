using System;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using YDrive.Models;
using YDrive.Services;

namespace YDrive.ViewModels;

// Platform detection helper
public static class PlatformHelper
{
    public static bool IsAndroid => OperatingSystem.IsAndroid();
    public static bool IsDesktop => !IsAndroid;
}

public partial class SettingsViewModel : ViewModelBase
{
    private AppSettings _settings => SettingsManager.Instance.Current;

    // Platform detection
    public bool IsAndroid => PlatformHelper.IsAndroid;
    public bool IsDesktop => PlatformHelper.IsDesktop;

    // General & Core
    [ObservableProperty] private bool _isGridView;
    [ObservableProperty] private bool _showFps;
    [ObservableProperty] private string _selectedCore = "Genesis Plus GX (Önerilen)";
    [ObservableProperty] private string _audioSamplerate = "44100";
    [ObservableProperty] private double _audioVolume = 1.0;
    [ObservableProperty] private string _ym2612Emulation = "mame";
    [ObservableProperty] private bool _svpSupport;
    [ObservableProperty] private string _biosPath = "";

    // SEGA CD BIOS Status — computed string/color properties for direct binding
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsUsBiosMissing))]
    [NotifyPropertyChangedFor(nameof(UsStatusText))]
    [NotifyPropertyChangedFor(nameof(UsStatusColor))]
    [NotifyPropertyChangedFor(nameof(IsAnyBiosLoaded))]
    [NotifyPropertyChangedFor(nameof(IsAllBiosLoaded))]
    [NotifyPropertyChangedFor(nameof(CanAddBios))]
    private bool _isUsBiosLoaded;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsEuBiosMissing))]
    [NotifyPropertyChangedFor(nameof(EuStatusText))]
    [NotifyPropertyChangedFor(nameof(EuStatusColor))]
    [NotifyPropertyChangedFor(nameof(IsAnyBiosLoaded))]
    [NotifyPropertyChangedFor(nameof(IsAllBiosLoaded))]
    [NotifyPropertyChangedFor(nameof(CanAddBios))]
    private bool _isEuBiosLoaded;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsJpBiosMissing))]
    [NotifyPropertyChangedFor(nameof(JpStatusText))]
    [NotifyPropertyChangedFor(nameof(JpStatusColor))]
    [NotifyPropertyChangedFor(nameof(IsAnyBiosLoaded))]
    [NotifyPropertyChangedFor(nameof(IsAllBiosLoaded))]
    [NotifyPropertyChangedFor(nameof(CanAddBios))]
    private bool _isJpBiosLoaded;

    // Inverse booleans for IsVisible binding (Avalonia ! prefix can be unreliable)
    public bool IsUsBiosMissing => !IsUsBiosLoaded;
    public bool IsEuBiosMissing => !IsEuBiosLoaded;
    public bool IsJpBiosMissing => !IsJpBiosLoaded;

    // Computed status text
    public string UsStatusText => IsUsBiosLoaded ? "Yüklendi (bios_CD_U.bin)" : "Yüklü Değil";
    public string EuStatusText => IsEuBiosLoaded ? "Yüklendi (bios_CD_E.bin)" : "Yüklü Değil";
    public string JpStatusText => IsJpBiosLoaded ? "Yüklendi (bios_CD_J.bin)" : "Yüklü Değil";

    // Computed status color as SolidColorBrush string
    public string UsStatusColor => IsUsBiosLoaded ? "#4CAF50" : "#8E9297";
    public string EuStatusColor => IsEuBiosLoaded ? "#4CAF50" : "#8E9297";
    public string JpStatusColor => IsJpBiosLoaded ? "#4CAF50" : "#8E9297";

    // Aggregate: at least one BIOS loaded (used for delete button visibility)
    public bool IsAnyBiosLoaded => IsUsBiosLoaded || IsEuBiosLoaded || IsJpBiosLoaded;
    
    // Aggregate: all BIOS loaded (used for add button visibility)
    public bool IsAllBiosLoaded => IsUsBiosLoaded && IsEuBiosLoaded && IsJpBiosLoaded;
    public bool CanAddBios => !IsAllBiosLoaded;

    private IPlatformService? _platformService;
    public IPlatformService? PlatformService
    {
        get => _platformService;
        set
        {
            _platformService = value;
            // PlatformService is set AFTER constructor by MainViewModel,
            // so we must re-check BIOS status once we have the correct path provider.
            if (value != null)
                RefreshBiosStatus();
        }
    }

    // Video & Display
    [ObservableProperty] private string _screenFilter = "None";
    [ObservableProperty] private bool _tubeTvEffectEnabled;
    [ObservableProperty] private string _aspectRatio = "Fit";

    // Mobile / System Lifecycle
    [ObservableProperty] private bool _autoSaveEnabled = true;
    [ObservableProperty] private bool _keepScreenOn = true;
    [ObservableProperty] private int _fastForwardSpeed = 2;

    // Controls (Desktop keyboard mapping)
    [ObservableProperty] private string _controllerType = "6-Button";
    [ObservableProperty] private string _p1Up = "W";
    [ObservableProperty] private string _p1Down = "S";
    [ObservableProperty] private string _p1Left = "A";
    [ObservableProperty] private string _p1Right = "D";
    [ObservableProperty] private string _p1A = "J";
    [ObservableProperty] private string _p1B = "K";
    [ObservableProperty] private string _p1C = "L";
    [ObservableProperty] private string _p1Start = "Enter";

    // Mobile / Touch Controls & HUD Editor
    [ObservableProperty] private bool _hapticFeedbackEnabled = true;
    [ObservableProperty] private bool _isHudEditorOpen;
    [ObservableProperty] private bool _isControlSelected;
    
    [ObservableProperty] private double _selectionBoxX;
    [ObservableProperty] private double _selectionBoxY;
    [ObservableProperty] private double _selectionBoxWidth;
    [ObservableProperty] private double _selectionBoxHeight;
    
    private string _selectedControlName = "";
    public string SelectedControlName
    {
        get => _selectedControlName;
        set
        {
            if (SetProperty(ref _selectedControlName, value))
            {
                UpdateSelectedSlidersFromControl();
            }
        }
    }

    private double _selectedControlScale = 1.0;
    public double SelectedControlScale
    {
        get => _selectedControlScale;
        set
        {
            if (SetProperty(ref _selectedControlScale, value))
            {
                ApplyScaleToSelectedControl(value);
            }
        }
    }

    private double _selectedControlOpacity = 0.65;
    public double SelectedControlOpacity
    {
        get => _selectedControlOpacity;
        set
        {
            if (SetProperty(ref _selectedControlOpacity, value))
            {
                ApplyOpacityToSelectedControl(value);
            }
        }
    }

    // Per-button properties
    [ObservableProperty] private double _touchDPadScale = 1.0;
    [ObservableProperty] private double _touchDPadOpacity = 0.65;
    [ObservableProperty] private double _touchAScale = 1.0;
    [ObservableProperty] private double _touchAOpacity = 0.65;
    [ObservableProperty] private double _touchBScale = 1.0;
    [ObservableProperty] private double _touchBOpacity = 0.65;
    [ObservableProperty] private double _touchCScale = 1.0;
    [ObservableProperty] private double _touchCOpacity = 0.65;
    [ObservableProperty] private double _touchXScale = 1.0;
    [ObservableProperty] private double _touchXOpacity = 0.65;
    [ObservableProperty] private double _touchYScale = 1.0;
    [ObservableProperty] private double _touchYOpacity = 0.65;
    [ObservableProperty] private double _touchZScale = 1.0;
    [ObservableProperty] private double _touchZOpacity = 0.65;
    [ObservableProperty] private double _touchStartScale = 1.0;
    [ObservableProperty] private double _touchStartOpacity = 0.65;

    // Touch Button Coordinates
    [ObservableProperty] private double _touchDPadX;
    [ObservableProperty] private double _touchDPadY;
    [ObservableProperty] private double _touchAX;
    [ObservableProperty] private double _touchAY;
    [ObservableProperty] private double _touchBX;
    [ObservableProperty] private double _touchBY;
    [ObservableProperty] private double _touchCX;
    [ObservableProperty] private double _touchCY;
    [ObservableProperty] private double _touchXX;
    [ObservableProperty] private double _touchXY;
    [ObservableProperty] private double _touchYX;
    [ObservableProperty] private double _touchYY;
    [ObservableProperty] private double _touchZX;
    [ObservableProperty] private double _touchZY;
    [ObservableProperty] private double _touchStartX;
    [ObservableProperty] private double _touchStartY;

    // Global HUD Settings
    [ObservableProperty] private double _touchOpacity = 1.0;
    [ObservableProperty] private double _touchScale = 1.0;

    // Key assignment waiting state (desktop only)
    [ObservableProperty] private bool _isAwaitingKey;
    [ObservableProperty] private string _awaitingKeyMessage = "";
    private string? _pendingAssignTarget;

    // About Modal
    [ObservableProperty] private bool _isAboutVisible;

    [RelayCommand]
    private void OpenAbout() => IsAboutVisible = true;

    [RelayCommand]
    private void CloseAbout() => IsAboutVisible = false;

    // Options
    public string[] AvailableCores { get; } = { "Genesis Plus GX (Önerilen)", "PicoDrive (Yüksek Performans)" };
    public string[] AudioRates { get; } = { "22050", "44100", "48000" };
    public string[] Ym2612Options { get; } = { "mame", "nuked" };
    public string[] ScreenFilters { get; } = { "None", "CRT", "LCD" };
    public string[] AspectRatioOptions { get; } = { "Fit", "4:3", "Stretch" };
    public string[] ControllerTypes { get; } = { "3-Button", "6-Button" };
    public int[] FastForwardSpeeds { get; } = { 2, 3, 4, 6, 8 };

    public SettingsViewModel()
    {
        LoadFromSettings();
        
        // Listen for changes saved by other views (like HudEditorViewModel)
        SettingsManager.Instance.SettingsChanged += (s, e) => 
        {
            LoadFromSettings();
        };
    }

    public void LoadFromSettings()
    {
        IsGridView = _settings.IsGridView;
        ShowFps = _settings.ShowFps;
        SelectedCore = string.IsNullOrEmpty(_settings.SelectedCore) ? "Genesis Plus GX (Önerilen)" : _settings.SelectedCore;
        AudioSamplerate = _settings.AudioSamplerate;
        AudioVolume = _settings.AudioVolume;
        Ym2612Emulation = _settings.Ym2612Emulation;
        ScreenFilter = _settings.ScreenFilter;
        TubeTvEffectEnabled = _settings.TubeTvEffectEnabled;
        AspectRatio = _settings.AspectRatio;
        SvpSupport = _settings.SvpSupport;
        BiosPath = _settings.BiosPath;
        AutoSaveEnabled = _settings.AutoSaveEnabled;
        KeepScreenOn = _settings.KeepScreenOn;
        FastForwardSpeed = _settings.FastForwardSpeed;

        ControllerType = _settings.ControllerType;
        HapticFeedbackEnabled = _settings.HapticFeedbackEnabled;

        TouchOpacity = _settings.TouchOpacity;
        TouchScale = _settings.TouchScale;


        TouchDPadScale = _settings.TouchDPadScale;
        TouchDPadOpacity = _settings.TouchDPadOpacity;
        TouchAScale = _settings.TouchAScale;
        TouchAOpacity = _settings.TouchAOpacity;
        TouchBScale = _settings.TouchBScale;
        TouchBOpacity = _settings.TouchBOpacity;
        TouchCScale = _settings.TouchCScale;
        TouchCOpacity = _settings.TouchCOpacity;
        TouchXScale = _settings.TouchXScale;
        TouchXOpacity = _settings.TouchXOpacity;
        TouchYScale = _settings.TouchYScale;
        TouchYOpacity = _settings.TouchYOpacity;
        TouchZScale = _settings.TouchZScale;
        TouchZOpacity = _settings.TouchZOpacity;
        TouchStartScale = _settings.TouchStartScale;
        TouchStartOpacity = _settings.TouchStartOpacity;

        TouchDPadX = _settings.TouchDPadX;
        TouchDPadY = _settings.TouchDPadY;
        TouchAX = _settings.TouchAX;
        TouchAY = _settings.TouchAY;
        TouchBX = _settings.TouchBX;
        TouchBY = _settings.TouchBY;
        TouchCX = _settings.TouchCX;
        TouchCY = _settings.TouchCY;
        TouchXX = _settings.TouchXX;
        TouchXY = _settings.TouchXY;
        TouchYX = _settings.TouchYX;
        TouchYY = _settings.TouchYY;
        TouchZX = _settings.TouchZX;
        TouchZY = _settings.TouchZY;
        TouchStartX = _settings.TouchStartX;
        TouchStartY = _settings.TouchStartY;

        // Failsafe for corrupted saved layouts (e.g. from previous bugs where Cancel saved 0 coords)
        // If TouchAX or TouchBX is 0, the layout is definitely corrupted since these buttons should be on the right side.
        if (_settings.IsCustomPositioned && (_settings.TouchAX <= 0 || _settings.TouchBX <= 0))
        {
            _settings.IsCustomPositioned = false;
        }

        // FIX: Ensure the ViewModel's Screen dimensions match the loaded layout
        // to prevent the HUD preview Canvas (which binds to these) from clipping.
        if (_settings.IsCustomPositioned && _settings.CustomLayoutScreenWidth > 100 && _settings.CustomLayoutScreenHeight > 100)
        {
            ScreenWidth = _settings.CustomLayoutScreenWidth;
            ScreenHeight = _settings.CustomLayoutScreenHeight;
        }
        else
        {
            // If it's the first time or reset, recalculate immediately to avoid 0,0 coordinates
            // at the top-left of the preview.
            AutoFitToScreen(ScreenWidth, ScreenHeight);
        }
        RefreshBiosStatus();
    }

    /// <summary>
    /// Returns the reliable "system" directory for BIOS files, matching LibretroCore.LoadCore logic.
    /// </summary>
    private string GetBiosSystemDirectory()
    {
        // On Android, Environment.GetFolderPath returns empty string,
        // so PlatformService.GetAppDirectory() must be checked FIRST.
        string baseDir = PlatformService?.GetAppDirectory() ?? "";
        if (string.IsNullOrEmpty(baseDir))
            baseDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrEmpty(baseDir))
            baseDir = AppDomain.CurrentDomain.BaseDirectory;
        return System.IO.Path.Combine(baseDir, "system");
    }

    private void RefreshBiosStatus()
    {
        string sysDir = GetBiosSystemDirectory();
        Console.WriteLine($"[BIOS] RefreshBiosStatus sysDir = {sysDir}");

        bool usExists = Services.BiosService.DetectRegionFromFile(System.IO.Path.Combine(sysDir, "bios_CD_U.bin")) == Services.BiosService.BiosRegion.US;
        bool euExists = Services.BiosService.DetectRegionFromFile(System.IO.Path.Combine(sysDir, "bios_CD_E.bin")) == Services.BiosService.BiosRegion.EU;
        bool jpExists = Services.BiosService.DetectRegionFromFile(System.IO.Path.Combine(sysDir, "bios_CD_J.bin")) == Services.BiosService.BiosRegion.JP;

        Console.WriteLine($"[BIOS] US={usExists}, EU={euExists}, JP={jpExists}");

        // Setting each [ObservableProperty] auto-fires PropertyChanged,
        // which cascades to all [NotifyPropertyChangedFor] targets.
        IsUsBiosLoaded = usExists;
        IsEuBiosLoaded = euExists;
        IsJpBiosLoaded = jpExists;

        _settings.IsUsBiosLoaded = usExists;
        _settings.IsEuBiosLoaded = euExists;
        _settings.IsJpBiosLoaded = jpExists;
    }

    [RelayCommand]
    private async Task DeleteBiosAsync()
    {
        if (PlatformService == null) return;

        bool confirmed = await PlatformService.ShowConfirmAsync(
            "BIOS Dosyalarını Sil",
            "Yüklü olan SEGA CD BIOS dosyalarını silmek istediğinize emin misiniz?",
            "Sil",
            "İptal");

        if (!confirmed) return;

        string sysDir = GetBiosSystemDirectory();
        string[] biosFiles = { "bios_CD_U.bin", "bios_CD_E.bin", "bios_CD_J.bin" };
        foreach (var file in biosFiles)
        {
            string path = System.IO.Path.Combine(sysDir, file);
            if (System.IO.File.Exists(path))
            {
                try { System.IO.File.Delete(path); } catch { }
            }
        }

        RefreshBiosStatus();
        SettingsManager.Instance.SaveSettings();
    }

    [RelayCommand]
    private async Task AddBiosAsync()
    {
        if (PlatformService == null) return;
        
        var results = await PlatformService.OpenMultipleFileDialogAsync("BIOS Dosyalarını Seç", "BIN Files|*.bin|All Files|*.*");
        if (results == null || results.Length == 0) return;

        string sysDir = GetBiosSystemDirectory();
        Console.WriteLine($"[BIOS] AddBiosAsync sysDir = {sysDir}");
        
        // Ensure system directory exists
        try { System.IO.Directory.CreateDirectory(sysDir); } catch { }

        int installedCount = 0;
        int unknownCount = 0;

        foreach (var biosFile in results)
        {
            if (string.IsNullOrWhiteSpace(biosFile)) continue;
            Console.WriteLine($"[BIOS] Processing file: {biosFile}");

            // Use BiosService for content-based detection (header + MD5)
            var region = BiosService.InstallBios(biosFile, sysDir);

            if (region != BiosService.BiosRegion.Unknown)
            {
                installedCount++;
                Console.WriteLine($"[BIOS] Detected region: {region}");
            }
            else
            {
                unknownCount++;
                Console.WriteLine($"[BIOS] Unknown region for: {biosFile}");
            }
        }

        // Immediately refresh UI
        RefreshBiosStatus();
        SettingsManager.Instance.SaveSettings();
        
        if (PlatformService != null)
        {
            if (installedCount > 0 && unknownCount == 0)
                await PlatformService.ShowMessageAsync("BIOS", $"{installedCount} BIOS dosyası başarıyla eklendi.");
            else if (installedCount > 0 && unknownCount > 0)
                await PlatformService.ShowMessageAsync("BIOS", $"{installedCount} BIOS eklendi, {unknownCount} dosya tanınamadı.");
            else if (unknownCount > 0)
                await PlatformService.ShowMessageAsync("BIOS", "Seçilen dosyalar geçerli SEGA CD BIOS dosyası olarak tanınamadı.");
        }
    }

    [ObservableProperty] private double _screenWidth = 800;
    [ObservableProperty] private double _screenHeight = 450;

    [RelayCommand]
    private void OpenHudEditor()
    {
        if (!_settings.IsCustomPositioned)
        {
            AutoFitToScreen(ScreenWidth, ScreenHeight);
        }
        else
        {
            ClampToScreen(ScreenWidth, ScreenHeight);
        }
        IsHudEditorOpen = true;
    }

    [RelayCommand]
    private void CloseHudEditor()
    {
        SaveTouchCoordinates();
        IsHudEditorOpen = false;
    }

    [RelayCommand]
    private void CancelHudEditor()
    {
        LoadFromSettings();
        IsHudEditorOpen = false;
    }

    [RelayCommand]
    public void ResetTouchCoordinates()
    {
        double scaleFactor = Math.Clamp(ScreenWidth / 1280.0, 1.0, 1.2);

        TouchDPadScale = scaleFactor;
        TouchDPadOpacity = 0.65;
        TouchAScale = scaleFactor;
        TouchAOpacity = 0.65;
        TouchBScale = scaleFactor;
        TouchBOpacity = 0.65;
        TouchCScale = scaleFactor;
        TouchCOpacity = 0.65;
        TouchXScale = scaleFactor;
        TouchXOpacity = 0.65;
        TouchYScale = scaleFactor;
        TouchYOpacity = 0.65;
        TouchZScale = scaleFactor;
        TouchZOpacity = 0.65;
        TouchStartScale = scaleFactor;
        TouchStartOpacity = 0.65;

        SelectedControlScale = scaleFactor;
        SelectedControlOpacity = 0.65;

        HapticFeedbackEnabled = true;

        // Kendi canvas boyutuna göre bağımsız hesapla
        AutoFitToScreen(ScreenWidth, ScreenHeight);

        // Seçim çerçevesini (mavi kutuyu) yeni konuma hemen adapte et
        UpdateSelectedSlidersFromControl();

        // Ayarlarda özel konumlandırmayı kaldır (farklı ekran boyutlarında kendi hesaplasın diye)
        _settings.IsCustomPositioned = false;
        
        // Hesaplanan yeni default değerleri _settings'e kaydet
        SaveTouchCoordinates();
        
        SettingsManager.Instance.SaveSettings();
    }

    public void AutoFitToScreen(double screenWidth, double screenHeight)
    {
        if (screenWidth <= 100 || screenHeight <= 100) return;

        ScreenWidth = screenWidth;
        ScreenHeight = screenHeight;

        double scaleFactor = Math.Clamp(screenWidth / 1280.0, 1.0, 1.2);

        TouchDPadScale = scaleFactor;
        TouchAScale = scaleFactor;
        TouchBScale = scaleFactor;
        TouchCScale = scaleFactor;
        TouchXScale = scaleFactor;
        TouchYScale = scaleFactor;
        TouchZScale = scaleFactor;
        TouchStartScale = scaleFactor;

        var coords = TouchLayoutService.CalculateDefaultCoordinates(screenWidth, screenHeight);
        TouchDPadX = coords.DPadX;
        TouchDPadY = coords.DPadY;
        TouchAX = coords.AX;
        TouchAY = coords.AY;
        TouchBX = coords.BX;
        TouchBY = coords.BY;
        TouchCX = coords.CX;
        TouchCY = coords.CY;
        TouchXX = coords.XX;
        TouchXY = coords.XY;
        TouchYX = coords.YX;
        TouchYY = coords.YY;
        TouchZX = coords.ZX;
        TouchZY = coords.ZY;
        TouchStartX = coords.StartX;
        TouchStartY = coords.StartY;
    }

    public void ClampToScreen(double screenWidth, double screenHeight)
    {
        if (screenWidth <= 100 || screenHeight <= 100) return;

        double lastW = _settings.CustomLayoutScreenWidth > 100 ? _settings.CustomLayoutScreenWidth : ScreenWidth;
        double lastH = _settings.CustomLayoutScreenHeight > 100 ? _settings.CustomLayoutScreenHeight : ScreenHeight;

        if (lastW > 100 && lastH > 100)
        {
            double diffX = screenWidth - lastW;
            double diffY = screenHeight - lastH;

            TouchDPadX = Math.Max(0, TouchDPadX);
            TouchDPadY = Math.Max(0, TouchDPadY + diffY);

            TouchAX = Math.Max(0, TouchAX + diffX);
            TouchAY = Math.Max(0, TouchAY + diffY);

            TouchBX = Math.Max(0, TouchBX + diffX);
            TouchBY = Math.Max(0, TouchBY + diffY);

            TouchCX = Math.Max(0, TouchCX + diffX);
            TouchCY = Math.Max(0, TouchCY + diffY);

            TouchXX = Math.Max(0, TouchXX + diffX);
            TouchXY = Math.Max(0, TouchXY + diffY);

            TouchYX = Math.Max(0, TouchYX + diffX);
            TouchYY = Math.Max(0, TouchYY + diffY);

            TouchZX = Math.Max(0, TouchZX + diffX);
            TouchZY = Math.Max(0, TouchZY + diffY);

            TouchStartX = Math.Max(0, TouchStartX + (diffX / 2));
            TouchStartY = Math.Max(0, TouchStartY + diffY);
        }

        // Fix: Update the observable properties so the preview Canvas resizes correctly!
        ScreenWidth = screenWidth;
        ScreenHeight = screenHeight;

        // Always update the settings layout sizes so future resizing uses the new baseline
        _settings.CustomLayoutScreenWidth = screenWidth;
        _settings.CustomLayoutScreenHeight = screenHeight;
    }

    public void SaveTouchCoordinates()
    {
        _settings.TouchDPadX = TouchDPadX;
        _settings.TouchDPadY = TouchDPadY;
        _settings.TouchAX = TouchAX;
        _settings.TouchAY = TouchAY;
        _settings.TouchBX = TouchBX;
        _settings.TouchBY = TouchBY;
        _settings.TouchCX = TouchCX;
        _settings.TouchCY = TouchCY;
        _settings.TouchXX = TouchXX;
        _settings.TouchXY = TouchXY;
        _settings.TouchYX = TouchYX;
        _settings.TouchYY = TouchYY;
        _settings.TouchZX = TouchZX;
        _settings.TouchZY = TouchZY;
        _settings.TouchStartX = TouchStartX;
        _settings.TouchStartY = TouchStartY;
        
        _settings.CustomLayoutScreenWidth = ScreenWidth;
        _settings.CustomLayoutScreenHeight = ScreenHeight;

        _settings.TouchDPadScale = TouchDPadScale;
        _settings.TouchDPadOpacity = TouchDPadOpacity;
        _settings.TouchAScale = TouchAScale;
        _settings.TouchAOpacity = TouchAOpacity;
        _settings.TouchBScale = TouchBScale;
        _settings.TouchBOpacity = TouchBOpacity;
        _settings.TouchCScale = TouchCScale;
        _settings.TouchCOpacity = TouchCOpacity;
        _settings.TouchXScale = TouchXScale;
        _settings.TouchXOpacity = TouchXOpacity;
        _settings.TouchYScale = TouchYScale;
        _settings.TouchYOpacity = TouchYOpacity;
        _settings.TouchZScale = TouchZScale;
        _settings.TouchZOpacity = TouchZOpacity;
        _settings.TouchStartScale = TouchStartScale;
        _settings.TouchStartOpacity = TouchStartOpacity;
        _settings.HapticFeedbackEnabled = HapticFeedbackEnabled;
    }

    [RelayCommand]
    private void AssignKey(string target)
    {
        _pendingAssignTarget = target;
        IsAwaitingKey = true;
        AwaitingKeyMessage = $"'{target}' için klavyeden bir tuşa basın...";
    }

    public void OnKeyPressed(string keyName)
    {
        if (!IsAwaitingKey || _pendingAssignTarget == null) return;

        switch (_pendingAssignTarget)
        {
            case "Up":    P1Up = keyName; break;
            case "Down":  P1Down = keyName; break;
            case "Left":  P1Left = keyName; break;
            case "Right": P1Right = keyName; break;
            case "A":     P1A = keyName; break;
            case "B":     P1B = keyName; break;
            case "C":     P1C = keyName; break;
            case "Start": P1Start = keyName; break;
        }

        IsAwaitingKey = false;
        _pendingAssignTarget = null;
        AwaitingKeyMessage = "";
    }

    [RelayCommand]
    private async Task BrowseBios()
    {
        await Task.CompletedTask;
    }

    [RelayCommand]
    private async Task ExportLogsAsync()
    {
        if (PlatformService == null) return;
        
        string logPath = DiagnosticLog.LogPath;
        if (string.IsNullOrEmpty(logPath) || !System.IO.File.Exists(logPath))
        {
            await PlatformService.ShowMessageAsync("Log Dışa Aktarma", "Aktarılacak log dosyası bulunamadı.");
            return;
        }

        string newFileName = $"ydrive_log_{DateTime.Now:yyyyMMdd_HHmmss}.txt";
        bool success = await PlatformService.ExportFileToDownloadsAsync(logPath, newFileName);
        
        if (success)
        {
            await PlatformService.ShowMessageAsync("Başarılı", $"Log dosyası '{newFileName}' adıyla İndirilenler klasörüne (veya Masaüstüne) aktarıldı.");
        }
        else
        {
            await PlatformService.ShowMessageAsync("Hata", "Log dosyası aktarılamadı. Gerekli izinlerin verildiğinden emin olun.");
        }
    }

    [RelayCommand]
    private void Save()
    {
        _settings.IsGridView = IsGridView;
        _settings.ShowFps = ShowFps;
        _settings.SelectedCore = SelectedCore;
        _settings.AudioSamplerate = AudioSamplerate;
        _settings.AudioVolume = AudioVolume;
        _settings.Ym2612Emulation = Ym2612Emulation;
        _settings.ScreenFilter = ScreenFilter;
        _settings.TubeTvEffectEnabled = TubeTvEffectEnabled;
        _settings.AspectRatio = AspectRatio;
        _settings.SvpSupport = SvpSupport;
        _settings.BiosPath = BiosPath;
        _settings.AutoSaveEnabled = AutoSaveEnabled;
        _settings.KeepScreenOn = KeepScreenOn;
        _settings.FastForwardSpeed = FastForwardSpeed;

        _settings.ControllerType = ControllerType;
        _settings.HapticFeedbackEnabled = HapticFeedbackEnabled;
        
        _settings.TouchOpacity = TouchOpacity;
        _settings.TouchScale = TouchScale;

        // Note: The rest of touch coordinates and scales are saved when Hud editor closes or reset is called
        SettingsManager.Instance.SaveSettings();
    }

    [RelayCommand]
    private void Cancel()
    {
        LoadFromSettings();
    }

    private void UpdateSelectedSlidersFromControl()
    {
        switch (SelectedControlName)
        {
            case "DPad": SelectedControlScale = TouchDPadScale; SelectedControlOpacity = TouchDPadOpacity; SelectionBoxX = TouchDPadX; SelectionBoxY = TouchDPadY; SelectionBoxWidth = 160; SelectionBoxHeight = 160; break;
            case "A": SelectedControlScale = TouchAScale; SelectedControlOpacity = TouchAOpacity; SelectionBoxX = TouchAX; SelectionBoxY = TouchAY; SelectionBoxWidth = 68; SelectionBoxHeight = 68; break;
            case "B": SelectedControlScale = TouchBScale; SelectedControlOpacity = TouchBOpacity; SelectionBoxX = TouchBX; SelectionBoxY = TouchBY; SelectionBoxWidth = 68; SelectionBoxHeight = 68; break;
            case "C": SelectedControlScale = TouchCScale; SelectedControlOpacity = TouchCOpacity; SelectionBoxX = TouchCX; SelectionBoxY = TouchCY; SelectionBoxWidth = 68; SelectionBoxHeight = 68; break;
            case "X": SelectedControlScale = TouchXScale; SelectedControlOpacity = TouchXOpacity; SelectionBoxX = TouchXX; SelectionBoxY = TouchXY; SelectionBoxWidth = 52; SelectionBoxHeight = 52; break;
            case "Y": SelectedControlScale = TouchYScale; SelectedControlOpacity = TouchYOpacity; SelectionBoxX = TouchYX; SelectionBoxY = TouchYY; SelectionBoxWidth = 52; SelectionBoxHeight = 52; break;
            case "Z": SelectedControlScale = TouchZScale; SelectedControlOpacity = TouchZOpacity; SelectionBoxX = TouchZX; SelectionBoxY = TouchZY; SelectionBoxWidth = 52; SelectionBoxHeight = 52; break;
            case "Start": SelectedControlScale = TouchStartScale; SelectedControlOpacity = TouchStartOpacity; SelectionBoxX = TouchStartX; SelectionBoxY = TouchStartY; SelectionBoxWidth = 80; SelectionBoxHeight = 40; break;
        }
    }

    private void ApplyScaleToSelectedControl(double scale)
    {
        switch (SelectedControlName)
        {
            case "DPad": TouchDPadScale = scale; break;
            case "A": TouchAScale = scale; break;
            case "B": TouchBScale = scale; break;
            case "C": TouchCScale = scale; break;
            case "X": TouchXScale = scale; break;
            case "Y": TouchYScale = scale; break;
            case "Z": TouchZScale = scale; break;
            case "Start": TouchStartScale = scale; break;
        }
    }

    private void ApplyOpacityToSelectedControl(double opacity)
    {
        switch (SelectedControlName)
        {
            case "DPad": TouchDPadOpacity = opacity; break;
            case "A": TouchAOpacity = opacity; break;
            case "B": TouchBOpacity = opacity; break;
            case "C": TouchCOpacity = opacity; break;
            case "X": TouchXOpacity = opacity; break;
            case "Y": TouchYOpacity = opacity; break;
            case "Z": TouchZOpacity = opacity; break;
            case "Start": TouchStartOpacity = opacity; break;
        }
    }
}
