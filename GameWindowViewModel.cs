using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using SegaEmulator.Audio;
using SegaEmulator.Core;
using SegaEmulator.Input;
using SegaEmulator.Models;
using SegaEmulator.Services;
using System.Linq;

namespace SegaEmulator.ViewModels;

/// <summary>
/// Ayrı emülasyon penceresi (GameWindow) için ViewModel.
/// Emülasyon çekirdeği, ses, video ve klavye girdilerini bu pencere bağlamında yönetir.
/// </summary>
public class GameWindowViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly LibretroCore _core;
    private readonly AudioManager _audio;
    private readonly SegaEmulator.Input.InputManager _input;
    private readonly GameItem _game;

    private WriteableBitmap? _screenBitmap;
    private int _currentWidth;
    private int _currentHeight;

    private byte[]? _frameBuffer;
    private int _frameBufWidth;
    private int _frameBufHeight;
    private int _frameBufPitch;

    private string _title = "YDrive";
    private string _statusText = "";
    private string _fpsText = "";
    private string _consoleText = "";
    private bool _isGameLoaded;
    private bool _isRunning;
    private bool _isPaused;
    private ImageSource? _screenImage;

    private string _notificationText = "";
    private bool _isNotificationVisible;

    public string NotificationText
    {
        get => _notificationText;
        set => SetField(ref _notificationText, value);
    }

    public bool IsNotificationVisible
    {
        get => _isNotificationVisible;
        set => SetField(ref _isNotificationVisible, value);
    }

    private async void ShowNotification(string message)
    {
        NotificationText = message;
        IsNotificationVisible = true;
        await System.Threading.Tasks.Task.Delay(3000);
        IsNotificationVisible = false;
    }

    public string Title
    {
        get => _title;
        set => SetField(ref _title, value);
    }

    public string StatusText
    {
        get => _statusText;
        set => SetField(ref _statusText, value);
    }

    public string FpsText
    {
        get => _fpsText;
        set => SetField(ref _fpsText, value);
    }

    public string ConsoleText
    {
        get => _consoleText;
        set => SetField(ref _consoleText, value);
    }

    public bool IsGameLoaded
    {
        get => _isGameLoaded;
        set 
        { 
            SetField(ref _isGameLoaded, value); 
            CommandManager.InvalidateRequerySuggested(); 
            OnPropertyChanged(nameof(StatusColor));
        }
    }

    public bool IsRunning
    {
        get => _isRunning;
        set 
        { 
            SetField(ref _isRunning, value); 
            CommandManager.InvalidateRequerySuggested(); 
            OnPropertyChanged(nameof(StatusColor));
            OnPropertyChanged(nameof(PauseButtonText));
        }
    }

    public bool IsPaused
    {
        get => _isPaused;
        set 
        { 
            SetField(ref _isPaused, value); 
            CommandManager.InvalidateRequerySuggested(); 
            OnPropertyChanged(nameof(StatusColor));
            OnPropertyChanged(nameof(PauseButtonText));
        }
    }

    public string PauseButtonText
    {
        get => IsPaused ? (string)Application.Current.Resources["Btn_Resume"] : (string)Application.Current.Resources["Btn_Pause"];
    }

    public Brush StatusColor
    {
        get
        {
            if (!IsGameLoaded) return new SolidColorBrush(Color.FromRgb(255, 59, 92)); // Red
            if (IsPaused) return new SolidColorBrush(Color.FromRgb(255, 165, 0)); // Orange
            if (IsRunning) return new SolidColorBrush(Color.FromRgb(0, 200, 150)); // Green
            return new SolidColorBrush(Color.FromRgb(255, 59, 92)); // Red
        }
    }

    public ImageSource? ScreenImage
    {
        get => _screenImage;
        set => SetField(ref _screenImage, value);
    }

    public double ScreenWidth => 640;
    public double ScreenHeight => 480;
    public BitmapScalingMode ScalingMode => BitmapScalingMode.NearestNeighbor;
    public Visibility CrtFilterVisibility => SettingsManager.Instance.Current.ScreenFilter == "CRT" ? Visibility.Visible : Visibility.Collapsed;
    public Visibility LcdFilterVisibility => SettingsManager.Instance.Current.ScreenFilter == "LCD" ? Visibility.Visible : Visibility.Collapsed;
    public Visibility TubeTvFilterVisibility => SettingsManager.Instance.Current.TubeTvEffectEnabled ? Visibility.Visible : Visibility.Collapsed;
    private bool _isFullscreen;
    public bool IsFullscreen
    {
        get => _isFullscreen;
        set
        {
            SetField(ref _isFullscreen, value);
            OnPropertyChanged(nameof(IsNotFullscreen));
            OnPropertyChanged(nameof(FullscreenIcon));
        }
    }
    public bool IsNotFullscreen => !IsFullscreen;
    public string FullscreenIcon => IsFullscreen ? (string)Application.Current.Resources["Msg_ExitFullscreen"] : (string)Application.Current.Resources["Msg_EnterFullscreen"];

    public SegaEmulator.Input.InputManager Input => _input;

    public ICommand StartCommand { get; }
    public ICommand PauseResumeCommand { get; }
    public ICommand StopCommand { get; }
    public ICommand ResetCommand { get; }
    public ICommand SaveStateCommand { get; }
    public ICommand LoadStateCommand { get; }
    public ICommand ToggleFullscreenCommand { get; }
    public ICommand TakeScreenshotCommand { get; }

    public GameWindowViewModel(GameItem game)
    {
        _game = game ?? throw new ArgumentNullException(nameof(game));
        Title = $"YDrive - {game.Title} ({game.ConsoleName})";
        StatusText = (string)Application.Current.Resources["Msg_Preparing"];

        _core = new LibretroCore();
        _audio = new AudioManager();
        _input = new SegaEmulator.Input.InputManager();

        StartCommand        = new RelayCommand(_ => StartEmulation(),    _ => IsGameLoaded && !IsRunning);
        PauseResumeCommand  = new RelayCommand(_ => TogglePauseResume(), _ => IsRunning);
        StopCommand         = new RelayCommand(_ => StopEmulation(),     _ => IsRunning || IsPaused);
        ResetCommand        = new RelayCommand(_ => ResetEmulation(),    _ => IsRunning);
        SaveStateCommand    = new RelayCommand(_ => SaveState(),         _ => IsRunning);
        LoadStateCommand    = new RelayCommand(_ => LoadState(),         _ => IsGameLoaded);
        ToggleFullscreenCommand = new RelayCommand(_ => IsFullscreen = !IsFullscreen);
        TakeScreenshotCommand = new RelayCommand(_ => TakeScreenshot(),  _ => IsRunning && _screenImage != null);

        _core.Callbacks.OnVideoFrame      += OnVideoFrame;
        _core.Callbacks.OnAudioSampleBatch += OnAudioBatch;
        _core.Callbacks.OnInputPoll        += OnInputPoll;
        _core.Callbacks.OnInputState       = _input.GetInputState;
        _core.OnStateChanged               += OnEmulationStateChanged;
        _core.OnFpsUpdated                 += OnFpsUpdated;
        _core.OnAudioSampleRateChanged     += OnAudioSampleRateChanged;

        SettingsManager.Instance.SettingsChanged += OnSettingsChanged;

        TryInitialize();
    }

    private void OnSettingsChanged(object? sender, EventArgs e)
    {
        OnPropertyChanged(nameof(ScreenWidth));
        OnPropertyChanged(nameof(ScreenHeight));
        OnPropertyChanged(nameof(ScalingMode));
        OnPropertyChanged(nameof(CrtFilterVisibility));
        OnPropertyChanged(nameof(LcdFilterVisibility));
        OnPropertyChanged(nameof(TubeTvFilterVisibility));
        if (!SettingsManager.Instance.Current.ShowFps) FpsText = "";
    }

    private void TryInitialize()
    {
        string baseDir = Path.GetDirectoryName(Environment.ProcessPath) ?? AppDomain.CurrentDomain.BaseDirectory;
        string ext = Path.GetExtension(_game.RomPath)?.ToLowerInvariant() ?? "";
        string dllName = (ext == ".32x") ? "picodrive_libretro.dll" : "genesis_plus_gx_libretro.dll";
        string corePath = Path.Combine(baseDir, "cores", dllName);

        if (_game.SystemType == SystemType.SegaCD)
        {
            string systemDir = Path.Combine(baseDir, "system");
            bool hasBiosU = File.Exists(Path.Combine(systemDir, "bios_CD_U.bin"));
            bool hasBiosE = File.Exists(Path.Combine(systemDir, "bios_CD_E.bin"));
            bool hasBiosJ = File.Exists(Path.Combine(systemDir, "bios_CD_J.bin"));
            if (!hasBiosU || !hasBiosE || !hasBiosJ)
            {
                MessageBox.Show("Eksik BIOS dosyaları tespit edildi. Lütfen Ayarlar menüsünden BIOS dosyalarını yükleyip tekrar deneyin.", "Oyun Başlatılamadı", MessageBoxButton.OK, MessageBoxImage.Warning);
                StatusText = "BIOS Eksik";
                return;
            }
        }

        if (!File.Exists(corePath))
        {
            string msg = string.Format((string)Application.Current.Resources["Msg_CoreNotFound"], corePath);
            string title = (string)Application.Current.Resources["Msg_Error"];
            MessageBox.Show(msg, title, MessageBoxButton.OK, MessageBoxImage.Error);
            StatusText = (string)Application.Current.Resources["Msg_CoreMissing"];
            return;
        }

        try
        {
            _core.LoadCore(corePath);
            ConsoleText = LibretroCore.GetConsoleDisplayName(_core.DetectedConsole);
            
            if (!string.IsNullOrEmpty(_game.RomPath) && File.Exists(_game.RomPath))
            {
                _audio.Initialize(44100);
                bool loaded = _core.LoadGame(_game.RomPath);
                if (loaded)
                {
                    IsGameLoaded = true;
                    StatusText = (string)Application.Current.Resources["Msg_GameStarted"];
                    StartEmulation();
                }
                else
                {
                    string msg = (string)Application.Current.Resources["Msg_RomLoadError"];
                    string title = (string)Application.Current.Resources["Msg_RomLoadErrorTitle"];
                    MessageBox.Show(msg, title, MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
            else
            {
                StatusText = (string)Application.Current.Resources["Msg_InvalidRom"];
            }
        }
        catch (Exception ex)
        {
            string msg = string.Format((string)Application.Current.Resources["Msg_LaunchError"], ex.Message);
            string title = (string)Application.Current.Resources["Msg_LaunchErrorTitle"];
            MessageBox.Show(msg, title, MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void StartEmulation()
    {
        _core.Start();
    }

    private void TogglePauseResume()
    {
        if (IsPaused)
        {
            _core.Resume();
            _audio.Resume();
        }
        else
        {
            _core.Pause();
            _audio.Pause();
        }
    }

    private void StopEmulation()
    {
        _core.Stop();
        _audio.ClearBuffer();
        FpsText = "";
        ScreenImage = null;
        StatusText = (string)Application.Current.Resources["Msg_Stopped"];
    }

    private void ResetEmulation()
    {
        _core.ResetConsole();
        _audio.ClearBuffer();
        if (IsPaused)
        {
            _core.Resume();
            _audio.Resume();
        }
    }

    private void SaveState()
    {
        var dialog = new SaveFileDialog
        {
            Title = (string)Application.Current.Resources["Msg_SaveStateTitle"],
            Filter = "Save State|*.state|All Files|*.*",
            FileName = $"{_game.Title}.state"
        };

        if (dialog.ShowDialog() == true)
        {
            bool success = _core.SaveStateToFile(dialog.FileName);
            string msg = success ? string.Format((string)Application.Current.Resources["Msg_StateSaved"], Path.GetFileName(dialog.FileName)) : (string)Application.Current.Resources["Msg_StateSaveFailed"];
            ShowNotification(msg);
        }
    }

    private void LoadState()
    {
        var dialog = new OpenFileDialog
        {
            Title = (string)Application.Current.Resources["Msg_LoadStateTitle"],
            Filter = "Save State|*.state|All Files|*.*"
        };

        if (dialog.ShowDialog() == true)
        {
            var result = _core.LoadStateFromFile(dialog.FileName);
            string msg;
            switch (result)
            {
                case LibretroCore.LoadStateResult.Success:
                    msg = string.Format((string)Application.Current.Resources["Msg_StateLoaded"], Path.GetFileName(dialog.FileName));
                    break;
                case LibretroCore.LoadStateResult.MismatchedRom:
                    msg = Application.Current.TryFindResource("Msg_StateMismatch") as string
                          ?? "❌ Bu kayıt farklı bir oyuna ait!";
                    break;
                default:
                    msg = (string)Application.Current.Resources["Msg_StateLoadFailed"];
                    break;
            }
            ShowNotification(msg);
        }
    }

    private void TakeScreenshot()
    {
        if (_screenImage == null) return;

        bool wasPlaying = IsRunning && !IsPaused;
        if (wasPlaying) TogglePauseResume(); // Pause during screenshot if running

        try
        {
            if (_screenImage is not BitmapSource bs) return;
            BitmapSource screenshot = bs.Clone();
            string timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            
            // Try to place in a Screenshots folder next to the app
            string baseDir = Path.GetDirectoryName(Environment.ProcessPath) ?? AppDomain.CurrentDomain.BaseDirectory;
            string screenshotDir = Path.Combine(baseDir, "Screenshots");
            
            string defaultPath = Path.Combine(screenshotDir, $"{_game.Title}_{timestamp}.png");

            var previewWindow = new SegaEmulator.Views.ScreenshotPreviewWindow(screenshot, defaultPath);
            previewWindow.Owner = Application.Current.Windows.OfType<Window>().FirstOrDefault(w => w.IsActive) ?? Application.Current.MainWindow;
            
            if (previewWindow.ShowDialog() == true && previewWindow.WasSaved)
            {
                ShowNotification((string)Application.Current.Resources["Msg_ScreenshotSaved"]);
            }
        }
        finally
        {
            if (wasPlaying) TogglePauseResume(); // Resume after
        }
    }

    private void OnVideoFrame(IntPtr data, uint width, uint height, nuint pitch)
    {
        if (data == IntPtr.Zero) return;

        try
        {
            int w = (int)width;
            int h = (int)height;
            int srcPitch = (int)pitch;
            int frameSize = srcPitch * h;

            if (_frameBuffer == null || _frameBuffer.Length < frameSize)
                _frameBuffer = new byte[frameSize];

            unsafe
            {
                fixed (byte* dst = _frameBuffer)
                {
                    Buffer.MemoryCopy((void*)data, dst, frameSize, frameSize);
                }
            }

            _frameBufWidth = w;
            _frameBufHeight = h;
            _frameBufPitch = srcPitch;

            Application.Current?.Dispatcher?.BeginInvoke(() =>
            {
                try { RenderFrameToScreen(); } catch { }
            });
        }
        catch { }
    }

    private void RenderFrameToScreen()
    {
        int w = _frameBufWidth;
        int h = _frameBufHeight;
        int srcPitch = _frameBufPitch;
        byte[]? frameData = _frameBuffer;
        if (frameData == null || w == 0 || h == 0) return;

        if (_screenBitmap == null || _currentWidth != w || _currentHeight != h)
        {
            _currentWidth = w;
            _currentHeight = h;

            var pixelFormat = _core.Callbacks.CurrentPixelFormat switch
            {
                RetroPixelFormat.FormatXRGB8888 => PixelFormats.Bgr32,
                RetroPixelFormat.FormatRGB565   => PixelFormats.Bgr565,
                _                               => PixelFormats.Bgr555
            };

            _screenBitmap = new WriteableBitmap(_currentWidth, _currentHeight, 96, 96, pixelFormat, null);
            ScreenImage = _screenBitmap;
        }

        _screenBitmap.Lock();
        try
        {
            int bytesPerPixel = _core.Callbacks.CurrentPixelFormat == RetroPixelFormat.FormatXRGB8888 ? 4 : 2;
            int dstStride = _screenBitmap.BackBufferStride;
            int copyBytes = Math.Min(_currentWidth * bytesPerPixel, Math.Min(srcPitch, dstStride));

            unsafe
            {
                byte* dst = (byte*)_screenBitmap.BackBuffer;
                fixed (byte* src = frameData)
                {
                    for (int y = 0; y < _currentHeight; y++)
                    {
                        Buffer.MemoryCopy(src + y * srcPitch, dst + y * dstStride, dstStride, copyBytes);
                    }
                }
            }

            _screenBitmap.AddDirtyRect(new Int32Rect(0, 0, _currentWidth, _currentHeight));
        }
        finally
        {
            _screenBitmap.Unlock();
        }
    }

    private void OnAudioBatch(IntPtr data, nuint frames)
    {
        _audio.WriteSamples(data, frames);
    }

    private void OnInputPoll() { }

    private void OnEmulationStateChanged(EmulationState state)
    {
        try
        {
            Application.Current?.Dispatcher?.Invoke(() =>
            {
                IsRunning = state == EmulationState.Running || state == EmulationState.Paused;
                IsPaused = state == EmulationState.Paused;

                StatusText = state switch
                {
                    EmulationState.Running => (string)Application.Current.Resources["Msg_Running"],
                    EmulationState.Paused  => (string)Application.Current.Resources["Msg_Paused"],
                    EmulationState.Stopped => (string)Application.Current.Resources["Msg_Stopped"],
                    _                      => StatusText
                };
            });
        }
        catch { }
    }

    private void OnFpsUpdated(double fps)
    {
        if (!SettingsManager.Instance.Current.ShowFps) return;

        try
        {
            Application.Current?.Dispatcher?.Invoke(() =>
            {
                FpsText = $"{fps:F1} FPS";
            });
        }
        catch { }
    }

    private void OnAudioSampleRateChanged(double sampleRate)
    {
        _audio.Initialize(sampleRate);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(name);
        return true;
    }

    public void Dispose()
    {
        _core.Dispose();
        _audio.Dispose();
        GC.SuppressFinalize(this);
    }
}
