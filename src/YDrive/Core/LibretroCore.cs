// ─────────────────────────────────────────────────────────────
//  LibretroCore.cs — Ana emülasyon çekirdeği yönetimi
//  DLL yükleme, oyun yaşam döngüsü, frame döngüsü, save state
// ─────────────────────────────────────────────────────────────

using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace SegaEmulator.Core;

/// <summary>
/// Emülasyon durumları.
/// </summary>
public enum EmulationState
{
    Stopped,
    Running,
    Paused
}

/// <summary>
/// Algılanan konsol tipi.
/// </summary>
public enum ConsoleType
{
    Unknown,
    MasterSystem,
    GameGear,
    Genesis,
    SegaCD,
    Sega32X
}

/// <summary>
/// Genesis Plus GX çekirdeğini yöneten ana sınıf.
/// ROM yükleme, emülasyon döngüsü, duraklatma, save state işlemleri.
/// </summary>
public class LibretroCore : IDisposable
{
    private readonly LibretroApi _api;
    private readonly LibretroCallbacks _callbacks;
    private Thread? _emulationThread;
    private volatile bool _running;
#pragma warning disable CS0414  // Atanır ama EmulationState üzerinden okunur; ileride kullanım için saklandı
    private volatile bool _paused;
#pragma warning restore CS0414
    private readonly object _pauseLock = new();
    private ManualResetEventSlim _pauseEvent = new(true);
    private IntPtr _currentRomDataPtr = IntPtr.Zero;

    // ROM yolunu UTF-8 null-terminated byte[] olarak pin'li tutarız;
    // böylece GC taşıyamaz ve C++ çekirdeği Türkçe karakterleri doğru okur.
    private GCHandle _currentRomPathHandle;
    private bool _romPathHandleAllocated;

    // ──── Durum bilgileri ────
    public EmulationState State { get; private set; } = EmulationState.Stopped;

    /// <summary>Load state işlemi sonucu</summary>
    public enum LoadStateResult { Success, MismatchedRom, Failed }
    private byte[]? _currentRomMd5; // Mevcut ROM'un MD5 hash değeri
    public ConsoleType DetectedConsole { get; private set; } = ConsoleType.Unknown;
    public string CoreName { get; private set; } = string.Empty;
    public string CoreVersion { get; private set; } = string.Empty;
    public string LoadedRomName { get; private set; } = string.Empty;
    public double TargetFps { get; private set; }
    public double CurrentFps { get; private set; }
    public double AudioSampleRate { get; private set; }
    public uint VideoWidth { get; private set; }
    public uint VideoHeight { get; private set; }

    public LibretroCallbacks Callbacks => _callbacks;

    [DllImport("winmm.dll", EntryPoint = "timeBeginPeriod", SetLastError = true)]
    private static extern uint TimeBeginPeriod(uint uMilliseconds);

    [DllImport("winmm.dll", EntryPoint = "timeEndPeriod", SetLastError = true)]
    private static extern uint TimeEndPeriod(uint uMilliseconds);

    /// <summary>
    /// Windows 8.3 kısa yolu üretir (ASCII-safe, fopen() uyumlu).
    /// Türkçe karakterli yolları çekirdek C runtime'ına güvenle aktarmak için kullanılır.
    /// </summary>
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetShortPathNameW(
        [MarshalAs(UnmanagedType.LPWStr)] string lpszLongPath,
        [MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder lpszShortPath,
        uint cchBuffer);

    // ──── Event'ler ────
    public event Action<EmulationState>? OnStateChanged;
    public event Action<double>? OnFpsUpdated;
    public event Action<double>? OnAudioSampleRateChanged;

    // ──── Çekirdek özellikleri ────
    /// <summary>
    /// true ise çekirdek data buffer'dan değil doğrudan dosya yolundan okur.
    /// Genesis Plus GX bu bayrağı true döndürür; bu yüzden kısa yol stratejisi zorunludur.
    /// </summary>
    private bool _coreNeedsFullPath;

    public LibretroCore()
    {
        _api = new LibretroApi();
        _callbacks = new LibretroCallbacks();
        _callbacks.OnSystemAvInfoChanged += OnSystemAvInfoChanged;
    }

    private void OnSystemAvInfoChanged(RetroSystemAvInfo avInfo)
    {
        TargetFps = avInfo.Timing.Fps;
        AudioSampleRate = avInfo.Timing.SampleRate;
        VideoWidth = avInfo.Geometry.BaseWidth;
        VideoHeight = avInfo.Geometry.BaseHeight;
        OnAudioSampleRateChanged?.Invoke(AudioSampleRate);
    }

    /// <summary>
    /// Genesis Plus GX çekirdeğini (DLL) yükler ve başlatır.
    /// </summary>
    public void LoadCore(string dllPath)
    {
        if (!File.Exists(dllPath))
            throw new FileNotFoundException(
                $"Emülatör çekirdeği (DLL) bulunamadı: {dllPath}\n" +
                $"Lütfen '{Path.GetFileName(dllPath)}' dosyasını 'cores/' klasörüne yerleştirin.");

        // Sistem dizinlerini ayarla
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        _callbacks.SystemDirectory = Path.Combine(baseDir, "system");
        _callbacks.SaveDirectory = Path.Combine(baseDir, "saves");
        _callbacks.CorePath = dllPath;

        // Kayıt dizinini oluştur
        Directory.CreateDirectory(_callbacks.SaveDirectory);
        Directory.CreateDirectory(_callbacks.SystemDirectory);

        // DLL'i yükle
        _api.LoadCore(dllPath);

        // ── Libretro spec: tüm callback'ler retro_init'den ÖNCE kaydedilmeli ──
        // Environment ve video callback'leri önce kaydet;
        // audio callback'leri de burada kayıt altına alınıyor.
        _callbacks.Initialize(_api);
        DiagnosticLog.Write("CORE", "Callback'ler kaydedildi (Init öncesi) — Environment, Video, AudioSample, AudioBatch, Input");

        // Çekirdeği başlat
        _api.Init!();
        DiagnosticLog.Write("CORE", "retro_init() tamamlandı");

        // Çekirdek bilgilerini al
        var sysInfo = new RetroSystemInfo();
        _api.GetSystemInfo!(ref sysInfo);
        CoreName    = Marshal.PtrToStringAnsi(sysInfo.LibraryName)    ?? "Unknown";
        CoreVersion = Marshal.PtrToStringAnsi(sysInfo.LibraryVersion) ?? "?";

        // NeedFullpath: true ise çekirdek data buffer'dan değil dosya yolundan okur.
        // Genesis Plus GX bu bayrağı true döndürür.
        _coreNeedsFullPath = sysInfo.NeedFullpath;

        DiagnosticLog.Write("CORE", $"Yüklendi: {CoreName} v{CoreVersion} | NeedFullPath: {_coreNeedsFullPath}");
        Debug.WriteLine($"[Core] Yüklendi: {CoreName} v{CoreVersion} | NeedFullPath: {_coreNeedsFullPath}");
    }

    /// <summary>
    /// ROM dosyasını yükler ve emülasyona hazırlar.
    /// </summary>
    public bool LoadGame(string romPath)
    {
        if (!_api.IsLoaded)
            throw new InvalidOperationException("Çekirdek yüklenmeden oyun yüklenemez.");

        if (!File.Exists(romPath))
            throw new FileNotFoundException($"ROM dosyası bulunamadı: {romPath}");

        Directory.CreateDirectory(_callbacks.SaveDirectory);

        // Çalışan emülasyonu durdur
        Stop();

        // ROM verisini oku
        if (_currentRomDataPtr != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(_currentRomDataPtr);
            _currentRomDataPtr = IntPtr.Zero;
        }

        // Önceki ROM yolu handle'ını serbest bırak
        if (_romPathHandleAllocated)
        {
            _currentRomPathHandle.Free();
            _romPathHandleAllocated = false;
        }

        byte[] romData = File.ReadAllBytes(romPath);
        _currentRomDataPtr = Marshal.AllocHGlobal(romData.Length);
        Marshal.Copy(romData, 0, _currentRomDataPtr, romData.Length);

        // Olası save state kontrolleri için mevcut ROM'un MD5'ini hesapla
        using (var md5 = System.Security.Cryptography.MD5.Create())
        {
            _currentRomMd5 = md5.ComputeHash(romData);
        }

        // ────────────────────────────────────────────────
        // ROM yolu stratejisi:
        //  • NeedFullpath = true  → çekirdek path'ten fopen() ile açıyor.
        //    Windows fopen() UTF-8 bilmez; ANSI bekler. Türkçe 'ğ' (U+011F)
        //    ANSI CP1254'te var ama CP1252'de yok — güvenilir tek çözüm:
        //    GetShortPathNameW ile 8.3 ASCII kısa yol al, onu ANSI olarak geçir.
        //    Bu durumda data=null + size=0 gönderiyoruz (çekirdek zaten
        //    dosyayı kendisi açıyor, buffer'a bakmayıyor).
        //  • NeedFullpath = false → çekirdek data buffer'dan okuyor.
        //    Path sadece isim tanıma için kullanılır; UTF-8 pin'li yol güvenli.
        // ────────────────────────────────────────────────
        IntPtr romPathPtr;
        IntPtr romDataForCore;
        nuint  romSizeForCore;

        if (_coreNeedsFullPath)
        {
            // GetShortPathNameW: Uzun Unicode yolu → 8.3 ASCII-safe kısa yol.
            // Örnek: C:\Users\Yiğit\... → C:\Users\YIT~1\...
            var shortPathBuilder = new System.Text.StringBuilder(1024);
            uint result = GetShortPathNameW(romPath, shortPathBuilder, (uint)shortPathBuilder.Capacity);

            string pathToUse;
            if (result > 0 && result < shortPathBuilder.Capacity)
            {
                pathToUse = shortPathBuilder.ToString();
                DiagnosticLog.Write("CORE", $"Kısa yol üretildi: {pathToUse}");
            }
            else
            {
                // GetShortPathNameW başarısız oldu (8.3 isimler devre dışı ise olabilir).
                // Fallback: orijinal UTF-8 yol — çalışmayabilir ama denemek zarar vermez.
                pathToUse = romPath;
                DiagnosticLog.Write("CORE", $"UYARI: GetShortPathNameW başarısız (hata={Marshal.GetLastWin32Error()}), orijinal yol kullanılıyor");
            }

            // ANSI güvenli kısa yolu null-terminated byte[] olarak pin'le
            byte[] pathBytes = Encoding.UTF8.GetBytes(pathToUse + "\0");
            _currentRomPathHandle      = GCHandle.Alloc(pathBytes, GCHandleType.Pinned);
            _romPathHandleAllocated    = true;
            romPathPtr     = _currentRomPathHandle.AddrOfPinnedObject();

            // NeedFullpath modunda: çekirdek dosyayı kendisi açıyor.
            // data + size göndermek gerekmez; null ve sıfır gönderiyoruz.
            romDataForCore = IntPtr.Zero;
            romSizeForCore = 0;
        }
        else
        {
            // Çekirdek data buffer kullanıyor; UTF-8 pin'li yol güvenli.
            byte[] pathBytes = Encoding.UTF8.GetBytes(romPath + "\0");
            _currentRomPathHandle   = GCHandle.Alloc(pathBytes, GCHandleType.Pinned);
            _romPathHandleAllocated = true;
            romPathPtr     = _currentRomPathHandle.AddrOfPinnedObject();
            romDataForCore = _currentRomDataPtr;
            romSizeForCore = (nuint)romData.Length;
        }

        var gameInfo = new RetroGameInfo
        {
            Path = romPathPtr,
            Data = romDataForCore,
            Size = romSizeForCore,
            Meta = IntPtr.Zero
        };

        // ── KRİTİK: Tüm callback'leri retro_load_game'den ÖNCE yeniden kaydet ──
        // Libretro spec: Callback'ler retro_load_game çağrısından önce geçerli olmalıdır.
        // Genesis Plus GX YM2612 FM çipini oyun yükleme sırasında başlatır;
        // audio callback'leri bu noktada zaten kayıtlı ve non-null olmalıdır.
        if (_callbacks.EnvironmentCallback != null)
            _api.SetEnvironment!(_callbacks.EnvironmentCallback);
        if (_callbacks.VideoRefreshCallback != null)
            _api.SetVideoRefresh!(_callbacks.VideoRefreshCallback);
        if (_callbacks.AudioSampleCallback != null)
            _api.SetAudioSample!(_callbacks.AudioSampleCallback);
        if (_callbacks.AudioSampleBatchCallback != null)
            _api.SetAudioSampleBatch!(_callbacks.AudioSampleBatchCallback);
        if (_callbacks.InputPollCallback != null)
            _api.SetInputPoll!(_callbacks.InputPollCallback);
        if (_callbacks.InputStateCallback != null)
            _api.SetInputState!(_callbacks.InputStateCallback);
        DiagnosticLog.Write("CORE",
            $"Tüm callback'ler yeniden kaydedildi — " +
            $"Env={_callbacks.EnvironmentCallback != null}, " +
            $"Video={_callbacks.VideoRefreshCallback != null}, " +
            $"AudioSample={_callbacks.AudioSampleCallback != null}, " +
            $"AudioBatch={_callbacks.AudioSampleBatchCallback != null}, " +
            $"InputPoll={_callbacks.InputPollCallback != null}, " +
            $"InputState={_callbacks.InputStateCallback != null}");

        DiagnosticLog.Write("CORE", $"retro_load_game çağrılıyor — NeedFullPath={_coreNeedsFullPath}, Size={romData.Length} bytes");
        bool success = _api.LoadGame!(ref gameInfo);

        if (!success)
        {
            Debug.WriteLine($"[Core] ROM yüklenemedi: {romPath}");
            DiagnosticLog.Write("CORE", $"HATA: retro_load_game false döndürdü");
            return false;
        }

        LoadedRomName = Path.GetFileNameWithoutExtension(romPath);
        DetectedConsole = DetectConsoleType(romPath);

        // Sega CD BRAM'i çekirdeğin kendi bram_load() fonksiyonu yönetir.
        // RETRO_MEMORY_SAVE_RAM sadece kartuş SRAM'i (Genesis/SMS/GG/32X) içindir.
        if (DetectedConsole != ConsoleType.SegaCD)
            LoadSram();
        else
            DiagnosticLog.Write("CORE", "Sega CD algılandı — BRAM yönetimi çekirdeğe bırakıldı (bram_load/bram_save)");

        // AV bilgilerini al
        var avInfo = new RetroSystemAvInfo();
        _api.GetSystemAvInfo!(ref avInfo);
        TargetFps = avInfo.Timing.Fps;
        AudioSampleRate = avInfo.Timing.SampleRate;
        VideoWidth = avInfo.Geometry.BaseWidth;
        VideoHeight = avInfo.Geometry.BaseHeight;

        Debug.WriteLine($"[Core] AV Bilgisi — FPS: {TargetFps:F2}, SampleRate: {AudioSampleRate:F0}, " +
                        $"Çözünürlük: {VideoWidth}x{VideoHeight}, AspectRatio: {avInfo.Geometry.AspectRatio:F3}");
        DiagnosticLog.Write("CORE", $"AV Bilgisi — FPS: {TargetFps:F2}, SampleRate: {AudioSampleRate:F0}, " +
                        $"Çözünürlük: {VideoWidth}x{VideoHeight}, AspectRatio: {avInfo.Geometry.AspectRatio:F3}");

        // SampleRate güvenlik kontrolü
        if (AudioSampleRate <= 0 || AudioSampleRate > 192000)
        {
            Debug.WriteLine($"[Core] ⚠ Geçersiz AudioSampleRate: {AudioSampleRate}, 44100'e ayarlanıyor");
            AudioSampleRate = 44100;
        }

        // Kontrol cihazını ayarla
        _api.SetControllerPortDevice!(0, RetroDevice.JOYPAD);
        _api.SetControllerPortDevice!(1, RetroDevice.JOYPAD);

        Debug.WriteLine($"[Core] ROM yüklendi: {LoadedRomName} | Konsol: {DetectedConsole} | " +
                        $"FPS: {TargetFps:F1} | SampleRate: {AudioSampleRate} | Çözünürlük: {VideoWidth}x{VideoHeight}");

        return true;
    }

    /// <summary>
    /// ROM uzantısından konsol tipini belirler.
    /// </summary>
    private static ConsoleType DetectConsoleType(string romPath)
    {
        string ext = Path.GetExtension(romPath).ToLowerInvariant();
        return ext switch
        {
            ".sms"                      => ConsoleType.MasterSystem,
            ".gg"                       => ConsoleType.GameGear,
            ".gen" or ".md" or ".bin"   => ConsoleType.Genesis,
            ".iso" or ".cue" or ".chd"  => ConsoleType.SegaCD,
            ".32x"                      => ConsoleType.Sega32X,
            _                           => ConsoleType.Unknown
        };
    }

    /// <summary>
    /// Konsol tipinin görüntü adını döndürür.
    /// </summary>
    public static string GetConsoleDisplayName(ConsoleType type) => type switch
    {
        ConsoleType.MasterSystem => "SEGA Master System",
        ConsoleType.GameGear     => "SEGA Game Gear",
        ConsoleType.Genesis      => "SEGA Genesis / Mega Drive",
        ConsoleType.SegaCD       => "SEGA CD / Mega CD",
        ConsoleType.Sega32X      => "SEGA 32X",
        _                        => "Bilinmeyen Konsol"
    };

    // ═══════════════════ Emülasyon Kontrolü ═══════════════════

    /// <summary>
    /// Emülasyonu başlatır (ayrı thread'de).
    /// </summary>
    public void Start()
    {
        if (State == EmulationState.Running) return;

        _running = true;
        _paused = false;
        _pauseEvent.Set();
        State = EmulationState.Running;
        OnStateChanged?.Invoke(State);

        _emulationThread = new Thread(EmulationLoop)
        {
            Name = "EmulationThread",
            IsBackground = true,
            Priority = ThreadPriority.AboveNormal
        };
        _emulationThread.Start();
    }

    /// <summary>
    /// Emülasyonu duraklatır.
    /// </summary>
    public void Pause()
    {
        if (State != EmulationState.Running) return;

        _paused = true;
        _pauseEvent.Reset();
        State = EmulationState.Paused;
        OnStateChanged?.Invoke(State);
    }

    /// <summary>
    /// Emülasyonu devam ettirir.
    /// </summary>
    public void Resume()
    {
        if (State != EmulationState.Paused) return;

        _paused = false;
        _pauseEvent.Set();
        State = EmulationState.Running;
        OnStateChanged?.Invoke(State);
    }

    /// <summary>
    /// Emülasyonu tamamen durdurur.
    /// </summary>
    public void Stop()
    {
        if (State == EmulationState.Stopped) return;

        _running = false;
        _pauseEvent.Set(); // Duraklama varsa açarak thread'in bitmesini sağla

        _emulationThread?.Join(2000);
        _emulationThread = null;

        if (_api.IsLoaded)
        {
            if (DetectedConsole != ConsoleType.SegaCD)
                SaveSram();
            _api.UnloadGame!();
        }

        if (_currentRomDataPtr != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(_currentRomDataPtr);
            _currentRomDataPtr = IntPtr.Zero;
        }

        // Pin'li ROM yolu handle'ını serbest bırak
        if (_romPathHandleAllocated)
        {
            _currentRomPathHandle.Free();
            _romPathHandleAllocated = false;
        }

        State = EmulationState.Stopped;
        DetectedConsole = ConsoleType.Unknown;
        LoadedRomName = string.Empty;
        OnStateChanged?.Invoke(State);
    }

    /// <summary>
    /// Emülasyonu resetler (konsolu yeniden başlatır).
    /// </summary>
    public void ResetConsole()
    {
        if (State == EmulationState.Stopped || !_api.IsLoaded) return;
        if (DetectedConsole != ConsoleType.SegaCD)
            SaveSram();
        _api.Reset!();
    }

    // ═══════════════════ Save State ═══════════════════

    /// <summary>
    /// Mevcut emülasyon durumunu kaydeder.
    /// </summary>
    public byte[]? SaveState()
    {
        if (State == EmulationState.Stopped || !_api.IsLoaded) return null;

        nuint size = _api.SerializeSize!();
        if (size == 0) return null;

        byte[] buffer = new byte[(int)size];
        IntPtr ptr = Marshal.AllocHGlobal((int)size);

        try
        {
            bool success = _api.Serialize!(ptr, size);
            if (success)
            {
                Marshal.Copy(ptr, buffer, 0, (int)size);
                return buffer;
            }
            return null;
        }
        finally
        {
            Marshal.FreeHGlobal(ptr);
        }
    }

    /// <summary>
    /// Kaydedilmiş emülasyon durumunu yükler.
    /// </summary>
    public bool LoadState(byte[] stateData)
    {
        if (State == EmulationState.Stopped || !_api.IsLoaded) return false;

        IntPtr ptr = Marshal.AllocHGlobal(stateData.Length);
        try
        {
            Marshal.Copy(stateData, 0, ptr, stateData.Length);
            return _api.Unserialize!(ptr, (nuint)stateData.Length);
        }
        finally
        {
            Marshal.FreeHGlobal(ptr);
        }
    }

    /// <summary>
    /// Save state'i dosyaya kaydeder (Başına magic+MD5 header ekleyerek).
    /// Header format: [4 byte magic "YDST"] + [16 byte ROM MD5] + [save state verisi]
    /// </summary>
    public bool SaveStateToFile(string path)
    {
        byte[]? data = SaveState();
        if (data == null) return false;

        using (var fs = new FileStream(path, FileMode.Create, FileAccess.Write))
        {
            if (_currentRomMd5 != null && _currentRomMd5.Length == 16)
            {
                // Yeni format: magic imzası + MD5 header
                byte[] magic = { (byte)'Y', (byte)'D', (byte)'S', (byte)'T' };
                fs.Write(magic, 0, 4);
                fs.Write(_currentRomMd5, 0, 16);
            }
            // Header'dan sonra (veya header olmadan) save state verisi
            fs.Write(data, 0, data.Length);
        }
        return true;
    }

    /// <summary>
    /// Save state'i dosyadan yükler.
    /// Header format: [4 byte magic "YDST"] + [16 byte ROM MD5] + [save state verisi]
    /// </summary>
    /// <returns>LoadStateResult: Success, MismatchedRom (farklı ROM), Failed (bozuk/eski format hatası)</returns>
    public LoadStateResult LoadStateFromFile(string path)
    {
        if (State == EmulationState.Stopped || !_api.IsLoaded) return LoadStateResult.Failed;
        if (!File.Exists(path)) return LoadStateResult.Failed;

        byte[] fileData = File.ReadAllBytes(path);
        if (fileData.Length < 4) return LoadStateResult.Failed;

        // Magic imzasını kontrol et: "YDST"
        bool hasYdstHeader = fileData[0] == (byte)'Y' &&
                             fileData[1] == (byte)'D' &&
                             fileData[2] == (byte)'S' &&
                             fileData[3] == (byte)'T';

        if (hasYdstHeader && fileData.Length >= 20)
        {
            // Yeni format: header'daki MD5'i al (byte 4..19)
            if (_currentRomMd5 != null && _currentRomMd5.Length == 16)
            {
                bool md5Match = true;
                for (int i = 0; i < 16; i++)
                {
                    if (fileData[4 + i] != _currentRomMd5[i])
                    {
                        md5Match = false;
                        break;
                    }
                }

                // MD5 uyusmuyorsa yükleme yapılmaz - üst katman bildirim gösterir
                if (!md5Match)
                    return LoadStateResult.MismatchedRom;
            }

            // İlk 20 byte'ı (4 magic + 16 MD5) atla ve geri kalanını state olarak yükle
            byte[] stateData = new byte[fileData.Length - 20];
            Array.Copy(fileData, 20, stateData, 0, stateData.Length);
            return LoadState(stateData) ? LoadStateResult.Success : LoadStateResult.Failed;
        }
        else
        {
            // Eski format (YDST header yok): doğrudan state olarak yükle
            return LoadState(fileData) ? LoadStateResult.Success : LoadStateResult.Failed;
        }
    }

    // ═══════════════════ Emülasyon Döngüsü ═══════════════════

    private void EmulationLoop()
    {
        bool timerAdjusted = false;
        try
        {
            if (OperatingSystem.IsWindows())
            {
                TimeBeginPeriod(1);
                timerAdjusted = true;
            }
        }
        catch { }

        try
        {
            var stopwatch = Stopwatch.StartNew();
            var fpsStopwatch = Stopwatch.StartNew();
            int frameCount = 0;
            double nextFrameTimeMs = 0;

            while (_running)
            {
                // Duraklama kontrolü
                _pauseEvent.Wait();
                if (!_running) break;

                try
                {
                    // Bir frame emülasyonu çalıştır
                    _api.Run!();
                }
                catch (Exception ex)
                {
                    Debug.WriteLine($"[Core] Emülasyon hatası: {ex.Message}");
                    _running = false;
                    break;
                }

                frameCount++;

                // FPS hesapla (her 500ms)
                if (fpsStopwatch.ElapsedMilliseconds >= 500)
                {
                    CurrentFps = frameCount / fpsStopwatch.Elapsed.TotalSeconds;
                    frameCount = 0;
                    fpsStopwatch.Restart();
                    OnFpsUpdated?.Invoke(CurrentFps);
                }

                // Frame zamanlama — hedef FPS'e göre duyarlı bekleme
                double targetFrameTime = 1000.0 / (TargetFps > 0 ? TargetFps : 60.0);
                nextFrameTimeMs += targetFrameTime;
                double currentMs = stopwatch.Elapsed.TotalMilliseconds;

                // Zamanlama çok geride kaldıysa resenkronize ol
                if (nextFrameTimeMs < currentMs - targetFrameTime * 2)
                {
                    nextFrameTimeMs = currentMs;
                }

                double waitMs = nextFrameTimeMs - currentMs;
                if (waitMs > 2.0)
                {
                    Thread.Sleep((int)(waitMs - 1.5));
                }

                // Sub-millisecond kısmını mikro spin/yield ile tamamla
                while (stopwatch.Elapsed.TotalMilliseconds < nextFrameTimeMs)
                {
                    Thread.Yield();
                }
            }
        }
        finally
        {
            if (timerAdjusted && OperatingSystem.IsWindows())
            {
                try { TimeEndPeriod(1); } catch { }
            }
        }
    }

    // ═══════════════════ IDisposable ═══════════════════

    private bool _disposed;

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        Stop();

        if (_api.IsLoaded)
        {
            _api.Deinit!();
        }

        _api.Dispose();
        _pauseEvent.Dispose();

        GC.SuppressFinalize(this);
    }

    // ═══════════════════ SRAM (Save RAM) Yönetimi ═══════════════════
    private const uint RETRO_MEMORY_SAVE_RAM = 0;

    private void LoadSram()
    {
        if (string.IsNullOrEmpty(LoadedRomName)) return;
        
        nuint size = _api.GetMemorySize!(RETRO_MEMORY_SAVE_RAM);
        IntPtr ptr = _api.GetMemoryData!(RETRO_MEMORY_SAVE_RAM);

        if (size > 0 && ptr != IntPtr.Zero)
        {
            string sramPath = Path.Combine(_callbacks.SaveDirectory, $"{LoadedRomName}.srm");
            if (File.Exists(sramPath))
            {
                byte[] data = File.ReadAllBytes(sramPath);
                int copyLength = Math.Min(data.Length, (int)size);
                Marshal.Copy(data, 0, ptr, copyLength);
                DiagnosticLog.Write("CORE", $"SRAM yüklendi: {copyLength} bytes");
            }
            else
            {
                DiagnosticLog.Write("CORE", $"Yeni oyun için SRAM dosyası bulunamadı. Çekirdeğin kendi oluşturduğu (formatlanmış) bellek yapısı korunuyor.");
            }
        }
    }

    private void SaveSram()
    {
        if (!_api.IsLoaded || string.IsNullOrEmpty(LoadedRomName)) return;
        
        nuint size = _api.GetMemorySize!(RETRO_MEMORY_SAVE_RAM);
        IntPtr ptr = _api.GetMemoryData!(RETRO_MEMORY_SAVE_RAM);

        if (size > 0 && ptr != IntPtr.Zero)
        {
            string sramPath = Path.Combine(_callbacks.SaveDirectory, $"{LoadedRomName}.srm");
            byte[] data = new byte[size];
            Marshal.Copy(ptr, data, 0, (int)size);
            File.WriteAllBytes(sramPath, data);
            DiagnosticLog.Write("CORE", $"SRAM kaydedildi: {size} bytes ({sramPath})");
        }
    }
}
