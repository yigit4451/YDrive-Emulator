// ─────────────────────────────────────────────────────────────
//  LibretroCore.cs — Ana emülasyon çekirdeği yönetimi
//  DLL yükleme, oyun yaşam döngüsü, frame döngüsü, save state
// ─────────────────────────────────────────────────────────────

using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace YDrive.Core;

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

    // ROM yolunu C-string olarak pin'li tutarız
    private IntPtr _currentRomPathPtr = IntPtr.Zero;

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

    /// <summary>
    /// BIOS eksik olduğunda LoadGame false döndürmeden önce bu mesaj doldurulur.
    /// ViewModel bu mesajı kullanıcıya gösterir.
    /// </summary>
    public string? BiosErrorMessage { get; private set; }

    public LibretroCallbacks Callbacks => _callbacks;

#if WINDOWS
    [DllImport("winmm.dll", EntryPoint = "timeBeginPeriod", SetLastError = true)]
    private static extern uint TimeBeginPeriod(uint uMilliseconds);

    [DllImport("winmm.dll", EntryPoint = "timeEndPeriod", SetLastError = true)]
    private static extern uint TimeEndPeriod(uint uMilliseconds);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetShortPathNameW(
        [MarshalAs(UnmanagedType.LPWStr)] string lpszLongPath,
        [MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder lpszShortPath,
        uint cchBuffer);
#else
    private static uint TimeBeginPeriod(uint u) => 0;
    private static uint TimeEndPeriod(uint u) => 0;
    private static uint GetShortPathNameW(string p, System.Text.StringBuilder sb, uint cap) { sb.Append(p); return (uint)p.Length; }
#endif

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
    /// Genesis Plus GX veya Picodrive çekirdeğini (DLL/SO) yükler ve başlatır.
    /// </summary>
    public void LoadCore(string dllPath, string baseDir = "")
    {
        if (!OperatingSystem.IsAndroid() && !File.Exists(dllPath))
            throw new FileNotFoundException(
                $"Emülatör çekirdeği bulunamadı: {dllPath}\n" +
                $"Lütfen '{Path.GetFileName(dllPath)}' dosyasını 'cores/' klasörüne yerleştirin.");

        // Sistem dizinlerini ayarla
        if (string.IsNullOrEmpty(baseDir))
        {
            baseDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrEmpty(baseDir)) baseDir = AppDomain.CurrentDomain.BaseDirectory;
        }

        _callbacks.SystemDirectory = Path.Combine(baseDir, "system");
        _callbacks.SaveDirectory = Path.Combine(baseDir, "saves");
        _callbacks.CorePath = dllPath;

        // Kayıt dizinini oluştur
        try { Directory.CreateDirectory(_callbacks.SaveDirectory); } catch { }
        try { Directory.CreateDirectory(_callbacks.SystemDirectory); } catch { }

        // DLL / SO yükle
        _api.LoadCore(dllPath);

        // ── Libretro spec: tüm callback'ler retro_init'den ÖNCE kaydedilmeli ──
        // Environment ve video callback'leri önce kaydet;
        // audio callback'leri de burada kayıt altına alınıyor.
        _callbacks.Initialize(_api);
        DiagnosticLog.Write("CORE", "Callback'ler kaydedildi (Init öncesi) — Environment, Video, AudioSample, AudioBatch, Input");

        // Çekirdeği başlat
        Console.WriteLine($"[YDrive-Core] retro_init çağrılıyor...");
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

        // Önceki ROM yolu pointer'ını serbest bırak
        if (_currentRomPathPtr != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(_currentRomPathPtr);
            _currentRomPathPtr = IntPtr.Zero;
        }

        DetectedConsole = DetectConsoleType(romPath);

        // Callback'e konsol tipini hemen bildir — GET_VARIABLE 'genesis_plus_gx_bios' doğru değeri döndürsün.
        // retro_init() sırasında da çekirdek bu değişkeni sorgulayabilir; bu yüzden mümkün olan en erken noktada set ediyoruz.
        _callbacks.CurrentConsoleType = DetectedConsole;
        DiagnosticLog.Write("CORE", $"Konsol tipi belirlendi: {DetectedConsole} | Callback güncellendi");

        // PicoDrive gibi çekirdekler bazen _coreNeedsFullPath false dönebilir ama yine de kendisi okuyabilir.
        // Bu yüzden katı engellemeyi kaldırıyoruz.
        if (DetectedConsole == ConsoleType.SegaCD && !_coreNeedsFullPath)
        {
            DiagnosticLog.Write("CORE", "UYARI: Bu çekirdek NeedFullPath desteklemediğini raporluyor ama Sega CD oyunu açılıyor. Devam ediliyor.");
        }

        // ──── PRE-LAUNCH BIOS KONTROLÜ (Henüz hiçbir pointer tahsis edilmeden) ────
        // BIOS eksikse retro_load_game hiç çağrılmaz; false döndürülerek ViewModel kullanıcıya gösterir.
        if (DetectedConsole == ConsoleType.SegaCD)
        {
            string sysDir = _callbacks.SystemDirectory;
            string[] biosCandidates =
            {
                Path.Combine(sysDir, "bios_CD_U.bin"),
                Path.Combine(sysDir, "bios_CD_E.bin"),
                Path.Combine(sysDir, "bios_CD_J.bin"),
                Path.Combine(sysDir, "us_scd1_9210.bin"),
                Path.Combine(sysDir, "eu_mcd1_9210.bin"),
                Path.Combine(sysDir, "jp_mcd1_9112.bin"),
            };

            bool hasValidBios = false;
            foreach (string biosPath in biosCandidates)
            {
                if (File.Exists(biosPath))
                {
                    long size = new FileInfo(biosPath).Length;
                    // Geçerli boyutlar: 128 KB (131072) veya 256 KB (262144)
                    if (size == 131072 || size == 262144)
                    {
                        DiagnosticLog.Write("BIOS", $"Geçerli BIOS bulundu: {Path.GetFileName(biosPath)} ({size / 1024} KB)");
                        hasValidBios = true;
                        break;
                    }
                    else
                    {
                        DiagnosticLog.Write("BIOS", $"Geçersiz boyut: {Path.GetFileName(biosPath)} = {size} byte (128KB/256KB bekleniyor)");
                    }
                }
            }

            if (!hasValidBios)
            {
                BiosErrorMessage = "Uygun SEGA CD BIOS dosyası bulunamadı (128KB/256KB olmalı).\n" +
                                   "Lütfen Ayarlar > Genel menüsünden geçerli bir BIOS ekleyin.";
                DiagnosticLog.Write("BIOS", $"HATA: Geçerli BIOS yok. System dizini: {sysDir}");
                return false;
            }
        }

        // ── CHD format için çekirdek destek kontrolü ──
        // libgenesis_plus_gx ve libpicodrive'ın bazı build'leri libchdr olmadan derlenir.
        // Bu durumda çekirdek chd_open() çağırır → fonksiyon yok → SIGSEGV.
        // Core'un CHD desteğini binary düzeyde kontrol etmek yerine,
        // RetroSystemInfo'dan need_fullpath ve supports_no_game flaglarını kullanıyoruz.
        // CHD desteği yoksa: çekirdek retro_load_game'den false döndürür — bu durumu
        // aşağıdaki hata mesajıyla kullanıcıya iletiyoruz.
        string romExtLower = Path.GetExtension(romPath).ToLowerInvariant();
        bool isChdFile = romExtLower == ".chd";

        if (isChdFile)
        {
            DiagnosticLog.Write("CHD", $"CHD dosyası tespit edildi: {Path.GetFileName(romPath)}");
            DiagnosticLog.Write("CHD", $"Çekirdek: {CoreName} v{CoreVersion} | NeedFullPath={_coreNeedsFullPath}");

            // Çekirdeğin CHD desteğini dolaylı olarak doğrula:
            // Genesis Plus GX'in resmi CHD-destekli build'i need_fullpath=true döndürür
            // VE RetroSystemInfo.ValidExtensions içinde '.chd' bulunur.
            // need_fullpath=false ise zaten CHD'yi buffer'dan okuyamaz → kesin başarısız.
            if (!_coreNeedsFullPath)
            {
                BiosErrorMessage = "Bu çekirdek CHD formatını desteklemiyor (need_fullpath=false).\n" +
                                   "Lütfen oyununuzu ISO veya CUE/BIN formatına dönüştürün.\n" +
                                   "Dönüşüm için: chdman extractcd -i oyun.chd -o oyun.cue";
                DiagnosticLog.Write("CHD", "HATA: Çekirdek need_fullpath=false → CHD desteği yok");
                return false;
            }
        }

        // ── CUE dosyası doğrulama (Eksik .bin dosyaları yüzünden Core kilitlenmesini önleme) ──
        if (romExtLower == ".cue")
        {
            try
            {
                string cueDir = Path.GetDirectoryName(romPath) ?? "";
                string[] lines = File.ReadAllLines(romPath);
                foreach (string line in lines)
                {
                    string trimmed = line.TrimStart();
                    if (trimmed.StartsWith("FILE ", StringComparison.OrdinalIgnoreCase))
                    {
                        string[] parts = trimmed.Split('"', StringSplitOptions.RemoveEmptyEntries);
                        if (parts.Length >= 2)
                        {
                            string binName = parts[1];
                            string binPath = Path.Combine(cueDir, binName);
                            if (!File.Exists(binPath))
                            {
                                BiosErrorMessage = $"Oyunun müzik/veri dosyası ({binName}) CUE dosyasının yanında bulunamadı!\n\nAndroid sistem kısıtlamaları sebebiyle çoklu dosyalar (.cue + .bin) dosya seçiciden tam okunamıyor. Lütfen SEGA CD oyunlarınızı tek parça .iso formatında yükleyin.";
                                DiagnosticLog.Write("CUE", $"HATA: Eksik track dosyası tespit edildi -> {binPath}");
                                return false; // Çekirdek açmaya çalışıp kilitlenmesin diye işlemi iptal et
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                DiagnosticLog.Write("CUE", $"CUE doğrulama hatası: {ex.Message}");
            }
        }

        IntPtr romPathPtr;
        IntPtr romDataForCore;
        nuint  romSizeForCore;

        if (_coreNeedsFullPath || DetectedConsole == ConsoleType.SegaCD)
        {
            string pathToUse = romPath;
            if (OperatingSystem.IsWindows())
            {
                var sb = new System.Text.StringBuilder(1024);
                uint res = GetShortPathNameW(romPath, sb, (uint)sb.Capacity);
                if (res > 0 && res < sb.Capacity)
                {
                    pathToUse = sb.ToString();
                    DiagnosticLog.Write("CORE", $"Kısa yol üretildi: {pathToUse}");
                }
                else
                {
                    DiagnosticLog.Write("CORE", $"UYARI: GetShortPathNameW başarısız (hata={Marshal.GetLastWin32Error()}), orijinal yol kullanılıyor");
                }
            }

            // NeedFullpath modunda: çekirdek dosyayı kendisi açıyor.
            // data + size göndermek gerekmez; null ve sıfır gönderiyoruz.
            _currentRomPathPtr = Marshal.StringToHGlobalAnsi(pathToUse);
            romPathPtr = _currentRomPathPtr;
            romDataForCore = IntPtr.Zero;
            romSizeForCore = 0;

            DiagnosticLog.Write("CORE",
                $"NeedFullPath modu: data=NULL, size=0 — çekirdek dosyayı {Path.GetExtension(romPath).ToUpper()} formatında kendisi açacak");
        }
        else
        {
            // Çekirdek data buffer kullanıyor (Kartuş oyunları).
            byte[] romData = File.ReadAllBytes(romPath);
            _currentRomDataPtr = Marshal.AllocHGlobal(romData.Length);
            Marshal.Copy(romData, 0, _currentRomDataPtr, romData.Length);

            using (var md5 = System.Security.Cryptography.MD5.Create())
            {
                _currentRomMd5 = md5.ComputeHash(romData);
            }

            _currentRomPathPtr = Marshal.StringToHGlobalAnsi(romPath);
            romPathPtr = _currentRomPathPtr;
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

        // (BIOS pre-launch check yukarda yapıldı — buraya geldiğimizde BIOS geçerli demektir)

        // ── KRİTİK NOT: Tüm callback'ler zaten LoadCore içinde (retro_init öncesi) kaydedildi ──
        // Libretro spec: retro_set_environment SADECE retro_init'den ÖNCE çağrılmalıdır.
        // İkinci kez çağrılması bazı çekirdeklerde (Genesis Plus GX gibi) bellek/durum bozulmalarına
        // ve siyah ekran (sessiz çökme) sorunlarına yol açar.
        /*
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
        */
        
        DiagnosticLog.Write("CORE", "Callback'ler retro_init öncesinde zaten kaydedilmişti. Yeniden kaydetme atlandı.");

        string sizeInfo = _coreNeedsFullPath ? "N/A (Direct File Access)" : $"{gameInfo.Size} bytes";
        DiagnosticLog.Write("CORE", $"retro_load_game çağrılıyor — NeedFullPath={_coreNeedsFullPath}, DataPtr={(long)romDataForCore}, Size={romSizeForCore}");
        System.Diagnostics.Debug.WriteLine($"[CORE] retro_load_game çağrılıyor. Path={romPath}");
        Console.WriteLine($"[YDrive-Core] retro_load_game çağrılıyor. Path: {romPath}");

        bool success = _api.LoadGame!(ref gameInfo);
        
        Console.WriteLine($"[YDrive-Core] retro_load_game sonucu: {success}");
        System.Diagnostics.Debug.WriteLine($"[CORE] retro_load_game tamamlandı. Sonuç: {success}");

        if (!success)
        {
            DiagnosticLog.Write("CORE", "HATA: retro_load_game false döndürdü.");
            return false;
        }

        DiagnosticLog.Write("CORE", "retro_load_game başarıyla tamamlandı.");

        LoadedRomName = Path.GetFileNameWithoutExtension(romPath);

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

        // ROM yolu pointer'ını serbest bırak
        if (_currentRomPathPtr != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(_currentRomPathPtr);
            _currentRomPathPtr = IntPtr.Zero;
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

    public void Reset() => ResetConsole();

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
                    if (frameCount < 5)
                    {
                        Console.WriteLine("[YDrive-Core] retro_run tetiklendi (Frame çağrısı yapılıyor).");
                    }
                    // Bir frame emülasyonu çalıştır
                    _api.Run!();
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[YDrive-Core] retro_run HATASI: {ex.Message}");
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

        if (_currentRomPathPtr != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(_currentRomPathPtr);
            _currentRomPathPtr = IntPtr.Zero;
        }

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

