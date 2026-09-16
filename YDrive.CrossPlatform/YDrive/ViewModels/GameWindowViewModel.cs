using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using YDrive.Core;
using YDrive.Models;
using YDrive.Services;

namespace YDrive.ViewModels;

public class SaveSlotItem
{
    public int SlotNumber { get; set; }
    public string Title { get; set; } = "";
    public string FilePath { get; set; } = "";
    public string DateFormatted { get; set; } = "";
    public string SizeFormatted { get; set; } = "";
}

public partial class GameWindowViewModel : ViewModelBase, IDisposable
{
    private readonly GameItem _game;
    private readonly IPlatformService _platformService;
    private LibretroCore? _core;
    private readonly HashSet<RetroJoypadButton> _pressedButtons = new();
    private readonly object _inputLock = new();

    public Action? OnCloseRequested { get; set; }

    public string GameTitle => !string.IsNullOrEmpty(_game?.Title) ? _game.Title : "SEGA Genesis";

    [ObservableProperty]
    private string _title = "YDrive Game Window";
    
    [ObservableProperty]
    private bool _isPaused;

    [ObservableProperty]
    private bool _isTopBarVisible = false;

    [ObservableProperty]
    private bool _isSaveLoadModalOpen;

    [ObservableProperty]
    private ObservableCollection<SaveSlotItem> _saveSlots = new();

    [ObservableProperty]
    private bool _hasSaveSlots;

    [ObservableProperty]
    private WriteableBitmap? _screenBitmap;

    [ObservableProperty]
    private bool _showFps;

    [ObservableProperty]
    private string _fpsText = "0 FPS";



    [ObservableProperty]
    private Avalonia.Media.Stretch _gameStretch = Avalonia.Media.Stretch.Uniform;

    // --- HUD Editor Properties ---
    [ObservableProperty]
    private bool _isEditMode;

    [ObservableProperty]
    private bool _isTouchControlsEnabled = true;

    // Positions
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

    // Global Scale & Opacity
    [ObservableProperty] private double _touchOpacity = 1.0;
    [ObservableProperty] private double _touchScale = 1.0;

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

    [ObservableProperty] private bool _isGameRunning = false;
    public GameWindowViewModel(GameItem game, IPlatformService platformService)
    {
        _game = game;
        _platformService = platformService;
        Title = $"{game.Title} - YDrive";
        LoadSettings();
        // Emulation start is now deferred to StartEmulationAsync() which is triggered by the UI's Loaded event.
    }

    // Design-time constructor
    public GameWindowViewModel()
    {
        _game = new GameItem();
        _platformService = null!;
    }

    private double _lastScreenWidth = 0;
    private double _lastScreenHeight = 0;

    private void OnSettingsChanged(object? sender, EventArgs e)
    {
        var settings = SettingsManager.Instance.Current;
        ShowFps = settings.ShowFps;
        TouchOpacity = settings.TouchOpacity;
        TouchScale = settings.TouchScale;
        
        TouchDPadScale = settings.TouchDPadScale;
        TouchDPadOpacity = settings.TouchDPadOpacity;
        TouchAScale = settings.TouchAScale;
        TouchAOpacity = settings.TouchAOpacity;
        TouchBScale = settings.TouchBScale;
        TouchBOpacity = settings.TouchBOpacity;
        TouchCScale = settings.TouchCScale;
        TouchCOpacity = settings.TouchCOpacity;
        TouchXScale = settings.TouchXScale;
        TouchXOpacity = settings.TouchXOpacity;
        TouchYScale = settings.TouchYScale;
        TouchYOpacity = settings.TouchYOpacity;
        TouchZScale = settings.TouchZScale;
        TouchZOpacity = settings.TouchZOpacity;
        TouchStartScale = settings.TouchStartScale;
        TouchStartOpacity = settings.TouchStartOpacity;
        GameStretch = settings.AspectRatio == "Stretch" ? Avalonia.Media.Stretch.Fill : Avalonia.Media.Stretch.Uniform;

        // Failsafe: if claims custom but coords are 0, it's a buggy save. Reset it!
        if (settings.IsCustomPositioned && (settings.TouchAX <= 0 || settings.TouchBX <= 0))
        {
            settings.IsCustomPositioned = false;
        }

        if (settings.IsCustomPositioned)
        {
            ApplyCustomCoordinates(settings);
        }
        else
        {
            if (_lastScreenWidth > 100 && _lastScreenHeight > 100)
            {
                AutoFitToScreen(_lastScreenWidth, _lastScreenHeight);
            }
        }
    }

    private void LoadSettings()
    {
        SettingsManager.Instance.LoadSettings();
        SettingsManager.Instance.SettingsChanged -= OnSettingsChanged;
        SettingsManager.Instance.SettingsChanged += OnSettingsChanged;

        var settings = SettingsManager.Instance.Current;
        ShowFps = settings.ShowFps;
        IsTouchControlsEnabled = true;

        TouchDPadScale = settings.TouchDPadScale;
        TouchDPadOpacity = settings.TouchDPadOpacity;
        TouchAScale = settings.TouchAScale;
        TouchAOpacity = settings.TouchAOpacity;
        TouchBScale = settings.TouchBScale;
        TouchBOpacity = settings.TouchBOpacity;
        TouchCScale = settings.TouchCScale;
        TouchCOpacity = settings.TouchCOpacity;
        TouchXScale = settings.TouchXScale;
        TouchXOpacity = settings.TouchXOpacity;
        TouchYScale = settings.TouchYScale;
        TouchYOpacity = settings.TouchYOpacity;
        TouchZScale = settings.TouchZScale;
        TouchZOpacity = settings.TouchZOpacity;
        TouchStartScale = settings.TouchStartScale;
        TouchStartOpacity = settings.TouchStartOpacity;
        GameStretch = settings.AspectRatio == "Stretch" ? Avalonia.Media.Stretch.Fill : Avalonia.Media.Stretch.Uniform;

        // Kayıtlı koordinatlar varsa yükle
        // Yoksa (tümü 0), OnAttachedToVisualTree/OnTouchCanvasSizeChanged gerçek ekran boyutuyla auto-fit yapacak
        // Failsafe: if claims custom but coords are 0, it's a buggy save. Reset it!
        if (settings.IsCustomPositioned && (settings.TouchAX <= 0 || settings.TouchBX <= 0))
        {
            settings.IsCustomPositioned = false;
        }

        if (settings.IsCustomPositioned)
        {
            ApplyCustomCoordinates(settings);
        }
        // else: Koordinatlar 0 kalır, view attach olunca gerçek ekran boyutuyla hesaplanır

        YDrive.Input.InputManager.Instance.OnGamepadActivity -= OnGamepadActivity;
        YDrive.Input.InputManager.Instance.OnGamepadActivity += OnGamepadActivity;

        if (YDrive.Input.InputManager.Instance.IsGamepadActive)
        {
            OnGamepadActivity();
        }

        YDrive.Input.InputManager.Instance.OnTopBarToggleRequested -= OnTopBarToggleRequested;
        YDrive.Input.InputManager.Instance.OnTopBarToggleRequested += OnTopBarToggleRequested;
    }

    private void OnTopBarToggleRequested()
    {
        Avalonia.Threading.Dispatcher.UIThread.Post(() =>
        {
            IsTopBarVisible = !IsTopBarVisible;
            if (IsTopBarVisible)
            {
                YDrive.Input.InputManager.Instance.CurrentMode = YDrive.Input.InputMode.GameOverlay;
                YDrive.Input.InputManager.Instance.ClearAllInputs();
                // Optionally pause here if desired: TogglePause(); 
                // In an emulator pausing is better.
                if (!IsPaused)
                {
                    IsPaused = true;
                    _core?.Pause();
                    _audioManager?.Pause();
                }
                
                // Let view know to focus overlay
                OnOverlayOpened?.Invoke();
            }
            else
            {
                YDrive.Input.InputManager.Instance.CurrentMode = YDrive.Input.InputMode.InGame;
                
                if (IsPaused)
                {
                    IsPaused = false;
                    _core?.Resume();
                    _audioManager?.Resume();
                }

                // Let view know to focus game canvas
                OnOverlayClosed?.Invoke();
            }
        });
    }

    public event Action? OnOverlayOpened;
    public event Action? OnOverlayClosed;

    private void OnGamepadActivity()
    {
        // Gamepad kullanıldığında dokunmatik kontrolleri gizle
        if (IsTouchControlsEnabled && TouchOpacity > 0.0)
        {
            Avalonia.Threading.Dispatcher.UIThread.Post(() =>
            {
                TouchOpacity = 0.0;
            });
        }
    }

    private void ApplyCustomCoordinates(AppSettings settings)
    {
        if (settings.CustomLayoutScreenWidth > 100 && settings.CustomLayoutScreenHeight > 100 &&
            _lastScreenWidth > 100 && _lastScreenHeight > 100)
        {
            double diffX = _lastScreenWidth - settings.CustomLayoutScreenWidth;
            double diffY = _lastScreenHeight - settings.CustomLayoutScreenHeight;

            TouchDPadX = Math.Max(0, settings.TouchDPadX);
            TouchDPadY = Math.Max(0, settings.TouchDPadY + diffY);

            TouchAX = Math.Max(0, settings.TouchAX + diffX);
            TouchAY = Math.Max(0, settings.TouchAY + diffY);

            TouchBX = Math.Max(0, settings.TouchBX + diffX);
            TouchBY = Math.Max(0, settings.TouchBY + diffY);

            TouchCX = Math.Max(0, settings.TouchCX + diffX);
            TouchCY = Math.Max(0, settings.TouchCY + diffY);

            TouchXX = Math.Max(0, settings.TouchXX + diffX);
            TouchXY = Math.Max(0, settings.TouchXY + diffY);

            TouchYX = Math.Max(0, settings.TouchYX + diffX);
            TouchYY = Math.Max(0, settings.TouchYY + diffY);

            TouchZX = Math.Max(0, settings.TouchZX + diffX);
            TouchZY = Math.Max(0, settings.TouchZY + diffY);

            TouchStartX = Math.Max(0, settings.TouchStartX + (diffX / 2));
            TouchStartY = Math.Max(0, settings.TouchStartY + diffY);
        }
        else
        {
            TouchDPadX = settings.TouchDPadX;
            TouchDPadY = settings.TouchDPadY;
            TouchAX = settings.TouchAX;
            TouchAY = settings.TouchAY;
            TouchBX = settings.TouchBX;
            TouchBY = settings.TouchBY;
            TouchCX = settings.TouchCX;
            TouchCY = settings.TouchCY;
            TouchXX = settings.TouchXX;
            TouchXY = settings.TouchXY;
            TouchYX = settings.TouchYX;
            TouchYY = settings.TouchYY;
            TouchZX = settings.TouchZX;
            TouchZY = settings.TouchZY;
            TouchStartX = settings.TouchStartX;
            TouchStartY = settings.TouchStartY;
        }
    }

    public void AutoFitToScreen(double screenWidth, double screenHeight)
    {
        if (screenWidth <= 100 || screenHeight <= 100) return;
        _lastScreenWidth = screenWidth;
        _lastScreenHeight = screenHeight;

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

        // Failsafe: Eğer koordinatlar sıfırsa veya ekrandan taşıyorsa, varsayılan formüle sıfırla
        if (TouchAX <= 0 || TouchAY <= 0 || TouchAX > screenWidth)
        {
            AutoFitToScreen(screenWidth > 0 ? screenWidth : 1280, screenHeight > 0 ? screenHeight : 720);
            return;
        }

        if (_lastScreenWidth > 100 && _lastScreenHeight > 100)
        {
            double diffX = screenWidth - _lastScreenWidth;
            double diffY = screenHeight - _lastScreenHeight;

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

        _lastScreenWidth = screenWidth;
        _lastScreenHeight = screenHeight;
    }

    public void InitializeButtonPositions(double screenWidth, double screenHeight)
    {
        if (screenWidth <= 100 || screenHeight <= 100) return;

        // Her açılışta veya attach/loaded anında koordinatların ekrana oturmasını garanti et
        if (!SettingsManager.Instance.Current.IsCustomPositioned || TouchAX <= 0 || TouchAY <= 0 || TouchAX > screenWidth)
        {
            AutoFitToScreen(screenWidth, screenHeight);
        }
        else
        {
            ClampToScreen(screenWidth, screenHeight);
        }
    }

    private Audio.AudioManager? _audioManager;

    public async Task StartEmulationAsync()
    {
        Console.WriteLine("[YDrive-Launch] GameView açılıyor...");
        
        try
        {
            _core = new LibretroCore();
            
            // Wire input query callback
            _core.Callbacks.OnInputState = (port, device, index, id) =>
            {
                short touchVal = 0;
                uint baseDevice = device & 0xFF;
                
                if (port == 0 && baseDevice == RetroDevice.JOYPAD)
                {
                    lock (_inputLock)
                    {
                        touchVal = _pressedButtons.Contains((RetroJoypadButton)id) ? (short)1 : (short)0;
                    }
                }
                
                short gamepadVal = YDrive.Input.InputManager.Instance.GetInputState(port, device, index, id);
                return (short)(touchVal | gamepadVal);
            };

            // Wire video frame callback
            _core.Callbacks.OnVideoFrame += HandleVideoFrame;

            // Wire audio callback
            _audioManager = new Audio.AudioManager();
            var settings = SettingsManager.Instance.Current;
            _audioManager.Volume = (float)settings.AudioVolume;

            // Platform audio init will be done after core reports sample rate
            _core.Callbacks.OnAudioSampleBatch += (data, frames) =>
            {
                _audioManager?.WriteSamples(data, frames);
            };

            // Dinamik Sample Rate Değişimi (SEGA CD CDDA oyunları için)
            _core.OnAudioSampleRateChanged += (newSampleRate) =>
            {
                // retro_load_game aşamasında arka arkaya çoklu çağrılar Android AudioTrack'i kilitler (Deadlock/Hang).
                // Oyun çalışana kadar bu dinamik değişiklikleri yoksayıyoruz, LoadGame sonrası zaten 1 kez çağrılacak.
                if (!IsGameRunning) return;

                if (_audioManager != null && newSampleRate > 0)
                {
                    System.Diagnostics.Debug.WriteLine($"[Audio] Core requested dynamic sample rate change to: {newSampleRate}");
                    // Değişimi ayrı bir thread'de yap ki C++ çekirdeği (retro_run) bloklanmasın!
                    Task.Run(() => InitializePlatformAudio(newSampleRate));
                }
            };

            // Wire FPS callback
            _core.OnFpsUpdated += (fps) =>
            {
                if (ShowFps)
                {
                    Avalonia.Threading.Dispatcher.UIThread.Post(() =>
                    {
                        FpsText = $"{fps:F1} FPS";
                    });
                }
            };

            // Load Core based on user selection
            string corePath;
            // Kullanıcı talebi: PicoDrive, SEGA 32X ve SEGA CD oyunlarında kullanılsın.
            // Diğer tüm sistemler (Genesis, vb.) her zaman Genesis Plus GX ile açılır.
            bool isPico = (_game.SystemType == SystemType.Sega32X || _game.SystemType == SystemType.SegaCD);

            if (OperatingSystem.IsAndroid())
            {
                corePath = isPico ? "libpicodrive_libretro_android.so" : "libgenesis_plus_gx_libretro_android.so";
            }
            else
            {
                string coreDll = isPico ? "picodrive_libretro.dll" : "genesis_plus_gx_libretro.dll";
                corePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "cores", coreDll);
            }

            Console.WriteLine("[YDrive-Launch] Seçilen Çekirdek: " + corePath);
            string appDir = _platformService?.GetAppDirectory() ?? "";
            _core.LoadCore(corePath, appDir);

            // Load Game
            if (!string.IsNullOrEmpty(_game.RomPath) && _core.LoadGame(_game.RomPath))
            {
                // Initialize audio with the core's reported sample rate
                // SEGA CD CDDA ses: 44100 Hz PCM. Core 0 döndürdüyse varsayılan 44100 kullan.
                double sampleRate = _core.AudioSampleRate > 0 && _core.AudioSampleRate <= 192000
                    ? _core.AudioSampleRate
                    : 44100.0;
                Debug.WriteLine($"[Audio] Ses başlatılıyor: {sampleRate} Hz (Core bildirdi: {_core.AudioSampleRate})");
                InitializePlatformAudio(sampleRate);

                IsGameRunning = true;
                YDrive.Input.InputManager.Instance.CurrentMode = YDrive.Input.InputMode.InGame;
                _core.Start();
            }
            else
            {
                // BIOS eksikse özel açıklayıcı mesaj göster
                string errorMsg = !string.IsNullOrEmpty(_core.BiosErrorMessage)
                    ? _core.BiosErrorMessage
                    : "ROM dosyası açılamadı. Detaylar için Ayarlar > Hakkında üzerinden logları kontrol edin.";
                
                Avalonia.Threading.Dispatcher.UIThread.Post(() =>
                {
                    _platformService?.ShowMessageAsync("❌ ROM Yükleme Hatası", errorMsg);
                });
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("[YDrive-ERROR] Başlatma Hatası: " + ex.ToString());
            Debug.WriteLine($"[GameWindowViewModel] Emulation start error: {ex}");
            _platformService?.ShowMessageAsync("Emülasyon Hatası", ex.Message);
        }
    }

    private void InitializePlatformAudio(double sampleRate)
    {
        if (_audioManager == null) return;
        
        // Ensure old track is stopped before initializing a new one (important for CDDA sample rate changes)
        _audioManager.PlatformStop?.Invoke();

        if (OperatingSystem.IsAndroid())
        {
            try
            {
                // Use Android AudioTrack via reflection/platform service
                var audioTrack = CreateAndroidAudioTrack((int)sampleRate);
                if (audioTrack != null)
                {
                    dynamic track = audioTrack;
                    _audioManager.PlatformInit = (sr) => { };
                    _audioManager.PlatformWrite = (buffer, offset, count) =>
                    {
                        try { track.Write(buffer, offset, count); } catch { }
                    };
                    _audioManager.PlatformPause = () => { try { track.Pause(); } catch { } };
                    _audioManager.PlatformResume = () => { try { track.Play(); } catch { } };
                    _audioManager.PlatformStop = () =>
                    {
                        try { track.Stop(); track.Release(); } catch { }
                    };
                    track.Play();
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[Audio] Android AudioTrack init failed: {ex.Message}");
            }
        }

        _audioManager.Initialize(sampleRate);
    }

    private static object? CreateAndroidAudioTrack(int sampleRate)
    {
        try
        {
            // Android.Media.AudioTrack via reflection for cross-platform compilation
            var audioTrackType = Type.GetType("Android.Media.AudioTrack, Mono.Android");
            var channelOutType = Type.GetType("Android.Media.ChannelOut, Mono.Android");
            var encodingType = Type.GetType("Android.Media.Encoding, Mono.Android");
            var audioUsageType = Type.GetType("Android.Media.AudioUsageKind, Mono.Android");
            var contentTypeType = Type.GetType("Android.Media.AudioContentType, Mono.Android");
            var streamType = Type.GetType("Android.Media.Stream, Mono.Android");

            if (audioTrackType == null) return null;

            // Get minimum buffer size
            var getMinBufSize = audioTrackType.GetMethod("GetMinBufferSize",
                new[] { typeof(int), channelOutType!, encodingType! });

            var stereo = Enum.ToObject(channelOutType!, 12); // ChannelOut.Stereo = 12
            var pcm16 = Enum.ToObject(encodingType!, 2);     // Encoding.Pcm16bit = 2

            int minBuf = (int)getMinBufSize!.Invoke(null, new object[] { sampleRate, stereo, pcm16 })!;
            int bufSize = Math.Max(minBuf, 4096);

            // Build AudioAttributes
            var attrBuilderType = Type.GetType("Android.Media.AudioAttributes+Builder, Mono.Android");
            var attrBuilder = Activator.CreateInstance(attrBuilderType!);
            var setUsage = attrBuilderType!.GetMethod("SetUsage");
            var setContentType = attrBuilderType.GetMethod("SetContentType");
            var buildAttr = attrBuilderType.GetMethod("Build");

            var usageGame = Enum.ToObject(audioUsageType!, 14); // AudioUsageKind.Game = 14
            var contentMusic = Enum.ToObject(contentTypeType!, 2); // AudioContentType.Music = 2

            setUsage!.Invoke(attrBuilder, new[] { usageGame });
            setContentType!.Invoke(attrBuilder, new[] { contentMusic });
            var audioAttributes = buildAttr!.Invoke(attrBuilder, null);

            // Build AudioFormat
            var audioFormatBuilderType = Type.GetType("Android.Media.AudioFormat+Builder, Mono.Android");
            var audioFormatBuilder = Activator.CreateInstance(audioFormatBuilderType!);
            var setEncoding = audioFormatBuilderType!.GetMethod("SetEncoding");
            var setSampleRate = audioFormatBuilderType.GetMethod("SetSampleRate");
            var setChannelMask = audioFormatBuilderType.GetMethod("SetChannelMask");
            var buildFmt = audioFormatBuilderType.GetMethod("Build");

            setEncoding!.Invoke(audioFormatBuilder, new[] { pcm16 });
            setSampleRate!.Invoke(audioFormatBuilder, new object[] { sampleRate });
            setChannelMask!.Invoke(audioFormatBuilder, new[] { stereo });
            var audioFormat = buildFmt!.Invoke(audioFormatBuilder, null);

            // Create AudioTrack via Builder
            var trackBuilderType = Type.GetType("Android.Media.AudioTrack+Builder, Mono.Android");
            var trackBuilder = Activator.CreateInstance(trackBuilderType!);
            var setAudioAttr = trackBuilderType!.GetMethod("SetAudioAttributes");
            var setAudioFmt = trackBuilderType.GetMethod("SetAudioFormat");
            var setBufferSz = trackBuilderType.GetMethod("SetBufferSizeInBytes");
            var buildTrack = trackBuilderType.GetMethod("Build");

            setAudioAttr!.Invoke(trackBuilder, new[] { audioAttributes });
            setAudioFmt!.Invoke(trackBuilder, new[] { audioFormat });
            setBufferSz!.Invoke(trackBuilder, new object[] { bufSize });
            var audioTrack = buildTrack!.Invoke(trackBuilder, null);

            Debug.WriteLine($"[Audio] Android AudioTrack created: sampleRate={sampleRate}, bufSize={bufSize}");
            return audioTrack;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[Audio] CreateAndroidAudioTrack failed: {ex.Message}");
            return null;
        }
    }

    private volatile int _framePending;
    private byte[]? _pixelCopyBuffer;

    private int _videoLogCounter = 0;

    private void HandleVideoFrame(IntPtr data, uint width, uint height, nuint pitch)
    {
        if (_videoLogCounter < 5)
        {
            Console.WriteLine($"[YDrive-Video] Kare geldi: {width}x{height}, pitch: {pitch}");
            _videoLogCounter++;
        }

        if (!IsGameRunning) return;
        if (data == IntPtr.Zero || width == 0 || height == 0) return;

        // Frame drop: if the UI thread hasn't rendered the previous frame yet, skip this one
        if (Interlocked.CompareExchange(ref _framePending, 1, 0) != 0)
            return;

        // Copy pixel data on emulation thread (so the pointer stays valid)
        int h = (int)height;
        int w = (int)width;
        int srcPitchBytes = (int)pitch;
        var fmt = _core?.Callbacks.CurrentPixelFormat ?? RetroPixelFormat.FormatRGB565;
        int bpp = (fmt == RetroPixelFormat.FormatXRGB8888) ? 4 : 2;
        int rowBytes = w * bpp;
        int requiredSize = h * rowBytes;

        if (_pixelCopyBuffer == null || _pixelCopyBuffer.Length < requiredSize)
        {
            _pixelCopyBuffer = new byte[requiredSize];
        }

        byte[] pixelCopy = _pixelCopyBuffer; // Reference for the closure

        unsafe
        {
            byte* src = (byte*)data;
            fixed (byte* dst = pixelCopy)
            {
                if (srcPitchBytes == rowBytes)
                {
                    // Fast path: direct copy if pitch matches row bytes
                    Buffer.MemoryCopy(src, dst, requiredSize, requiredSize);
                }
                else
                {
                    // Pitch differs, copy row by row
                    for (int y = 0; y < h; y++)
                    {
                        Buffer.MemoryCopy(src + y * srcPitchBytes, dst + y * rowBytes, rowBytes, rowBytes);
                    }
                }
            }
        }

        Avalonia.Threading.Dispatcher.UIThread.Post(() =>
        {
            if (!IsGameRunning) return;
            try
            {
                if (ScreenBitmap == null || ScreenBitmap.PixelSize.Width != w || ScreenBitmap.PixelSize.Height != h)
                {
                    ScreenBitmap = new WriteableBitmap(
                        new PixelSize(w, h),
                        new Vector(96, 96),
                        PixelFormat.Bgra8888,
                        AlphaFormat.Opaque);
                }

                using var buf = ScreenBitmap.Lock();
                unsafe
                {
                    fixed (byte* pixPtr = pixelCopy)
                    {
                        if (fmt == RetroPixelFormat.FormatRGB565)
                        {
                            ushort* src = (ushort*)pixPtr;
                            uint* dst = (uint*)buf.Address;
                            int srcPitch = rowBytes / 2;
                            int dstPitch = buf.RowBytes / 4;

                            for (int y = 0; y < h; y++)
                            {
                                ushort* srcRow = src + (y * srcPitch);
                                uint* dstRow = dst + (y * dstPitch);

                                for (int x = 0; x < w; x++)
                                {
                                    ushort p = srcRow[x];
                                    byte r = (byte)((p >> 11) & 0x1F);
                                    byte g = (byte)((p >> 5) & 0x3F);
                                    byte b2 = (byte)(p & 0x1F);

                                    r = (byte)((r * 527 + 23) >> 6);
                                    g = (byte)((g * 259 + 33) >> 6);
                                    b2 = (byte)((b2 * 527 + 23) >> 6);

                                    dstRow[x] = 0xFF000000u | ((uint)r << 16) | ((uint)g << 8) | (uint)b2;
                                }
                            }
                        }
                        else if (fmt == RetroPixelFormat.Format0RGB1555)
                        {
                            ushort* src = (ushort*)pixPtr;
                            uint* dst = (uint*)buf.Address;
                            int srcPitch = rowBytes / 2;
                            int dstPitch = buf.RowBytes / 4;

                            for (int y = 0; y < h; y++)
                            {
                                ushort* srcRow = src + (y * srcPitch);
                                uint* dstRow = dst + (y * dstPitch);

                                for (int x = 0; x < w; x++)
                                {
                                    ushort p = srcRow[x];
                                    byte r = (byte)((p >> 10) & 0x1F);
                                    byte g = (byte)((p >> 5) & 0x1F);
                                    byte b2 = (byte)(p & 0x1F);

                                    r = (byte)((r * 527 + 23) >> 6);
                                    g = (byte)((g * 527 + 23) >> 6);
                                    b2 = (byte)((b2 * 527 + 23) >> 6);

                                    dstRow[x] = 0xFF000000u | ((uint)r << 16) | ((uint)g << 8) | (uint)b2;
                                }
                            }
                        }
                        else
                        {
                            // XRGB8888 -> BGRA8888 with Alpha = 0xFF
                            uint* src = (uint*)pixPtr;
                            uint* dst = (uint*)buf.Address;
                            int srcPitch = rowBytes / 4;
                            int dstPitch = buf.RowBytes / 4;

                            for (int y = 0; y < h; y++)
                            {
                                uint* srcRow = src + (y * srcPitch);
                                uint* dstRow = dst + (y * dstPitch);

                                for (int x = 0; x < w; x++)
                                {
                                    dstRow[x] = srcRow[x] | 0xFF000000u;
                                }
                            }
                        }
                    }
                }

                OnPropertyChanged(nameof(ScreenBitmap));
                OnFrameAvailable?.Invoke();
            }
            catch { }
            finally
            {
                Interlocked.Exchange(ref _framePending, 0);
            }
        }, Avalonia.Threading.DispatcherPriority.Render);
    }

    public event Action? OnFrameAvailable;

    public void SetButtonState(RetroJoypadButton button, bool pressed)
    {
        lock (_inputLock)
        {
            if (pressed)
                _pressedButtons.Add(button);
            else
                _pressedButtons.Remove(button);
        }
    }

    public void ClearButtonStates()
    {
        lock (_inputLock)
        {
            _pressedButtons.Clear();
        }
    }

    [RelayCommand]
    public void ToggleTopBar()
    {
        IsTopBarVisible = !IsTopBarVisible;
    }

    [RelayCommand]
    private void ToggleEditMode()
    {
        IsEditMode = !IsEditMode;
        if (IsEditMode)
        {
            IsPaused = true;
            _core?.Pause();
            _audioManager?.Pause();
        }
        else
        {
            IsPaused = false;
            _core?.Resume();
            _audioManager?.Resume();
            SaveTouchCoordinates();
            _platformService?.ShowMessageAsync("Kontroller", "Düzenleme kaydedildi!");
        }
    }

    public void SaveTouchCoordinates()
    {
        // Anti-Corruption: Boyutlar sıfır veya eksiyse ASLA kaydetme
        if (TouchAX <= 0 || TouchAY <= 0 || TouchDPadX <= 0)
        {
            return;
        }

        var settings = SettingsManager.Instance.Current;
        settings.TouchDPadX = TouchDPadX;
        settings.TouchDPadY = TouchDPadY;
        settings.TouchAX = TouchAX;
        settings.TouchAY = TouchAY;
        settings.TouchBX = TouchBX;
        settings.TouchBY = TouchBY;
        settings.TouchCX = TouchCX;
        settings.TouchCY = TouchCY;
        settings.TouchXX = TouchXX;
        settings.TouchXY = TouchXY;
        settings.TouchYX = TouchYX;
        settings.TouchYY = TouchYY;
        settings.TouchZX = TouchZX;
        settings.TouchZY = TouchZY;
        settings.TouchStartX = TouchStartX;
        settings.TouchStartY = TouchStartY;
        
        settings.CustomLayoutScreenWidth = _lastScreenWidth;
        settings.CustomLayoutScreenHeight = _lastScreenHeight;

        settings.TouchDPadScale = TouchDPadScale;
        settings.TouchDPadOpacity = TouchDPadOpacity;
        settings.TouchAScale = TouchAScale;
        settings.TouchAOpacity = TouchAOpacity;
        settings.TouchBScale = TouchBScale;
        settings.TouchBOpacity = TouchBOpacity;
        settings.TouchCScale = TouchCScale;
        settings.TouchCOpacity = TouchCOpacity;
        settings.TouchXScale = TouchXScale;
        settings.TouchXOpacity = TouchXOpacity;
        settings.TouchYScale = TouchYScale;
        settings.TouchYOpacity = TouchYOpacity;
        settings.TouchZScale = TouchZScale;
        settings.TouchZOpacity = TouchZOpacity;
        settings.TouchStartScale = TouchStartScale;
        settings.TouchStartOpacity = TouchStartOpacity;
        SettingsManager.Instance.SaveSettings();
    }

    [RelayCommand]
    private void TogglePause()
    {
        IsPaused = !IsPaused;
        if (IsPaused)
        {
            _core?.Pause();
            _audioManager?.Pause();
        }
        else
        {
            _core?.Resume();
            _audioManager?.Resume();
        }

        string msg = IsPaused ? "Oyun duraklatıldı ⏸" : "Oyun devam ediyor ▶";
        _platformService?.ShowMessageAsync("Durum", msg);
    }

    [RelayCommand]
    private void OpenSaveLoadModal()
    {
        IsSaveLoadModalOpen = true;
        YDrive.Input.InputManager.Instance.CurrentMode = YDrive.Input.InputMode.GameOverlay;
        if (!IsPaused)
        {
            IsPaused = true;
            _core?.Pause();
            _audioManager?.Pause();
        }
        RefreshSaveSlots();
    }

    [RelayCommand]
    private void CloseSaveLoadModal()
    {
        IsSaveLoadModalOpen = false;
        YDrive.Input.InputManager.Instance.CurrentMode = IsTopBarVisible 
            ? YDrive.Input.InputMode.GameOverlay 
            : YDrive.Input.InputMode.InGame;
            
        if (IsPaused)
        {
            IsPaused = false;
            _core?.Resume();
            _audioManager?.Resume();
        }
    }

    public void RefreshSaveSlots()
    {
        try
        {
            var appDir = _platformService?.GetAppDirectory() ?? AppDomain.CurrentDomain.BaseDirectory;
            var savesDir = Path.Combine(appDir, "Saves");
            if (!Directory.Exists(savesDir))
            {
                SaveSlots = new ObservableCollection<SaveSlotItem>();
                HasSaveSlots = false;
                return;
            }

            var romName = Path.GetFileNameWithoutExtension(_game.RomPath);
            if (string.IsNullOrEmpty(romName)) romName = "game";

            var files = Directory.GetFiles(savesDir, $"{romName}*.state");
            var slotList = new List<SaveSlotItem>();
            int index = 1;

            var sortedFiles = files.Select(f => new FileInfo(f))
                                   .OrderByDescending(f => f.LastWriteTime);

            foreach (var fi in sortedFiles)
            {
                slotList.Add(new SaveSlotItem
                {
                    SlotNumber = index++,
                    Title = $"Kayıt Slotu #{index - 1}",
                    FilePath = fi.FullName,
                    DateFormatted = fi.LastWriteTime.ToString("dd.MM.yyyy HH:mm:ss"),
                    SizeFormatted = $"{Math.Max(1, fi.Length / 1024)} KB"
                });
            }

            SaveSlots = new ObservableCollection<SaveSlotItem>(slotList);
            HasSaveSlots = SaveSlots.Count > 0;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[GameWindowViewModel] RefreshSaveSlots error: {ex.Message}");
        }
    }

    [RelayCommand]
    private async Task CreateNewSaveAsync()
    {
        try
        {
            var appDir = _platformService?.GetAppDirectory() ?? AppDomain.CurrentDomain.BaseDirectory;
            var savesDir = Path.Combine(appDir, "Saves");
            Directory.CreateDirectory(savesDir);

            var romName = Path.GetFileNameWithoutExtension(_game.RomPath);
            if (string.IsNullOrEmpty(romName)) romName = "game";

            string timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            string statePath = Path.Combine(savesDir, $"{romName}_slot_{timestamp}.state");

            if (_core != null && _core.State != EmulationState.Stopped)
            {
                bool success = _core.SaveStateToFile(statePath);
                if (success)
                {
                    RefreshSaveSlots();
                    if (_platformService != null)
                        await _platformService.ShowMessageAsync("Kayıt Başarılı", "Yeni kayıt oluşturuldu! 💾");
                    return;
                }
            }

            if (_platformService != null)
                await _platformService.ShowMessageAsync("Kayıt", "Kayıt oluşturulamadı.");
        }
        catch (Exception ex)
        {
            if (_platformService != null)
                await _platformService.ShowMessageAsync("Kayıt Hatası", ex.Message);
        }
    }

    [RelayCommand]
    private async Task LoadSlotAsync(SaveSlotItem? slot)
    {
        if (slot == null || !File.Exists(slot.FilePath)) return;

        try
        {
            if (_core != null && _core.State != EmulationState.Stopped)
            {
                var res = _core.LoadStateFromFile(slot.FilePath);
                if (res == LibretroCore.LoadStateResult.Success)
                {
                    IsSaveLoadModalOpen = false;
                    IsPaused = false;
                    _core.Resume();
                    _audioManager?.Resume();
                    await _platformService.ShowMessageAsync("Yükleme Başarılı", $"{slot.Title} yüklendi! ▶");
                    return;
                }
            }

            await _platformService.ShowMessageAsync("Yükleme", "Kayıt dosyası yüklenemedi.");
        }
        catch (Exception ex)
        {
            await _platformService.ShowMessageAsync("Yükleme Hatası", ex.Message);
        }
    }

    [RelayCommand]
    private async Task OverwriteSlotAsync(SaveSlotItem? slot)
    {
        if (slot == null) return;

        try
        {
            if (_core != null && _core.State != EmulationState.Stopped)
            {
                bool success = _core.SaveStateToFile(slot.FilePath);
                if (success)
                {
                    RefreshSaveSlots();
                    await _platformService.ShowMessageAsync("Kayıt Güncellendi", $"{slot.Title} üzerine kaydedildi! 💾");
                    return;
                }
            }

            await _platformService.ShowMessageAsync("Kayıt", "Kayıt güncellenemedi.");
        }
        catch (Exception ex)
        {
            await _platformService.ShowMessageAsync("Kayıt Hatası", ex.Message);
        }
    }

    [RelayCommand]
    private async Task DeleteSlotAsync(SaveSlotItem? slot)
    {
        if (slot == null) return;
        try
        {
            if (File.Exists(slot.FilePath))
            {
                File.Delete(slot.FilePath);
            }
            RefreshSaveSlots();
            await _platformService.ShowMessageAsync("Kayıt Silindi", $"{slot.Title} silindi.");
        }
        catch (Exception ex)
        {
            await _platformService.ShowMessageAsync("Silme Hatası", ex.Message);
        }
    }

    [RelayCommand]
    private async Task TakeScreenshotAsync()
    {
        try
        {
            if (ScreenBitmap == null)
            {
                if (_platformService != null)
                    await _platformService.ShowMessageAsync("Ekran Görüntüsü", "Görüntü henüz hazır değil.");
                return;
            }

            using var memoryStream = new MemoryStream();
            ScreenBitmap.Save(memoryStream);
            byte[] imageBytes = memoryStream.ToArray();

            var romName = Path.GetFileNameWithoutExtension(_game.RomPath);
            if (string.IsNullOrEmpty(romName)) romName = "game";
            string fileName = $"YDrive_{romName}_{DateTime.Now:yyyyMMdd_HHmmss}.png";

            if (_platformService != null)
            {
                bool success = await _platformService.SaveImageToGalleryAsync(imageBytes, fileName);
                if (success)
                {
                    await _platformService.ShowMessageAsync("Ekran Görüntüsü", "Görsel galeriye kaydedildi! 📸");
                }
                else
                {
                    await _platformService.ShowMessageAsync("Ekran Görüntüsü", "Galeriye kaydedilemedi.");
                }
            }
        }
        catch (Exception ex)
        {
            if (_platformService != null)
                await _platformService.ShowMessageAsync("Ekran Görüntüsü Hatası", ex.Message);
        }
    }

    [RelayCommand]
    private async Task ResetAsync()
    {
        _core?.Reset();
        IsPaused = false;
        await _platformService.ShowMessageAsync("Sıfırla", "Oyun yeniden başlatıldı 🔄");
    }

    [RelayCommand]
    private async Task StopAsync()
    {
        Dispose();
        OnCloseRequested?.Invoke();
        await Task.CompletedTask;
    }

    public void Dispose()
    {
        try
        {
            IsPaused = true;
            IsGameRunning = false;
            YDrive.Input.InputManager.Instance.CurrentMode = YDrive.Input.InputMode.MainMenu;
            
            if (OperatingSystem.IsAndroid())
            {
                // Try to release AudioTrack via platform call
                _audioManager?.PlatformStop?.Invoke();
            }
            _audioManager?.Dispose();
            _audioManager = null;
            _core?.Stop();
            _core?.Dispose();
            _core = null;
        }
        catch { }
    }
}
