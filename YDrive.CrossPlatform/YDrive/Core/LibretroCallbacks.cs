// ─────────────────────────────────────────────────────────────
//  LibretroCallbacks.cs — Çekirdek callback yönetimi
//  Video, ses, input ve environment callback'lerini yönetir
// ─────────────────────────────────────────────────────────────

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace YDrive.Core;

/// <summary>
/// Genesis Plus GX çekirdeğinden gelen callback'leri yönetir.
/// GC tarafından toplanmaması için delegate'ler static field olarak saklanır.
/// </summary>
public class LibretroCallbacks
{
    // ──── Callback delegate referansları (GC koruması) ────
    // Bu alanlar static olmasa da, LibretroCore içinde instance tutularak
    // GC'nin delegate'leri toplaması engellenir.

    public RetroEnvironmentDelegate? EnvironmentCallback { get; private set; }
    public RetroVideoRefreshDelegate? VideoRefreshCallback { get; private set; }
    public RetroAudioSampleDelegate? AudioSampleCallback { get; private set; }
    public RetroAudioSampleBatchDelegate? AudioSampleBatchCallback { get; private set; }
    public RetroInputPollDelegate? InputPollCallback { get; private set; }
    public RetroInputStateDelegate? InputStateCallback { get; private set; }
    private RetroLogPrintfDelegate? _logPrintfCallback;

    // ──── Piksel formatı ────
    public RetroPixelFormat CurrentPixelFormat { get; private set; } = RetroPixelFormat.FormatXRGB8888;

    // ──── Sistem dizinleri ────
    private string _systemDirectory = "";
    private string _saveDirectory = "";

    private IntPtr _systemDirAnsi = IntPtr.Zero;
    private IntPtr _saveDirAnsi = IntPtr.Zero;

    public string SystemDirectory
    {
        get => _systemDirectory;
        set
        {
            _systemDirectory = value;
            RefreshSystemDirPin();
        }
    }

    public string SaveDirectory
    {
        get => _saveDirectory;
        set
        {
            _saveDirectory = value;
            RefreshSaveDirPin();
        }
    }

    public string CorePath { get; set; } = string.Empty;

    /// <summary>
    /// Yüklenen konsolun tipi — BIOS variable'ının doğru değerini belirlemek için kullanılır.
    /// </summary>
    public ConsoleType CurrentConsoleType { get; set; } = ConsoleType.Unknown;

    private void RefreshSystemDirPin()
    {
        if (_systemDirAnsi != IntPtr.Zero) { Marshal.FreeHGlobal(_systemDirAnsi); _systemDirAnsi = IntPtr.Zero; }
        if (string.IsNullOrEmpty(_systemDirectory)) return;
        string dir = _systemDirectory.TrimEnd(Path.DirectorySeparatorChar, '/');
        _systemDirAnsi = Marshal.StringToHGlobalAnsi(dir);
    }

    private void RefreshSaveDirPin()
    {
        if (_saveDirAnsi != IntPtr.Zero) { Marshal.FreeHGlobal(_saveDirAnsi); _saveDirAnsi = IntPtr.Zero; }
        if (string.IsNullOrEmpty(_saveDirectory)) return;
        string dir = _saveDirectory.TrimEnd(Path.DirectorySeparatorChar, '/');
        _saveDirAnsi = Marshal.StringToHGlobalAnsi(dir);
    }



    // ──── Event'ler — dışarıya veri aktarımı ────

    /// <summary>Video frame hazır olduğunda tetiklenir.</summary>
    public event Action<IntPtr, uint, uint, nuint>? OnVideoFrame;

    /// <summary>Ses örnekleri geldiğinde tetiklenir.</summary>
    public event Action<IntPtr, nuint>? OnAudioSampleBatch;

    /// <summary>Input yoklama zamanı geldiğinde tetiklenir.</summary>
    public event Action? OnInputPoll;

    /// <summary>Belirli bir butonun durumu sorulduğunda tetiklenir.</summary>
    public Func<uint, uint, uint, uint, short>? OnInputState { get; set; }

    /// <summary>Sistem AV bilgisi değiştiğinde tetiklenir.</summary>
    public event Action<RetroSystemAvInfo>? OnSystemAvInfoChanged;

    /// <summary>Log mesajı geldiğinde tetiklenir.</summary>
#pragma warning disable CS0067
    public event Action<RetroLogLevel, string>? OnLogMessage;
#pragma warning restore CS0067

    /// <summary>
    /// Tüm callback'leri başlatır ve çekirdeğe kaydeder.
    /// </summary>
    public void Initialize(LibretroApi api)
    {
        // Delegate'leri oluştur ve referanslarını sakla
        EnvironmentCallback = EnvironmentHandler;
        VideoRefreshCallback = VideoRefreshHandler;
        AudioSampleCallback = AudioSampleHandler;
        AudioSampleBatchCallback = AudioSampleBatchHandler;
        InputPollCallback = InputPollHandler;
        InputStateCallback = InputStateHandler;
        _logPrintfCallback = LogPrintfHandler;

        // Çekirdeğe callback'leri kaydet
        api.SetEnvironment!(EnvironmentCallback);
        api.SetVideoRefresh!(VideoRefreshCallback);
        api.SetAudioSample!(AudioSampleCallback);
        api.SetAudioSampleBatch!(AudioSampleBatchCallback);
        api.SetInputPoll!(InputPollCallback);
        api.SetInputState!(InputStateCallback);
    }

    // ═══════════════════ Environment Callback ═══════════════════

    private Dictionary<string, IntPtr> _variablePtrCache = new();

    private bool EnvironmentHandler(uint cmd, IntPtr data)
    {
        switch (cmd)
        {
            case RetroEnvironment.SET_PIXEL_FORMAT:
                {
                    if (data != IntPtr.Zero)
                    {
                        CurrentPixelFormat = (RetroPixelFormat)Marshal.ReadInt32(data);
                    }
                    return true;
                }

            case RetroEnvironment.GET_SYSTEM_DIRECTORY:
                {
                    if (data != IntPtr.Zero && _systemDirAnsi != IntPtr.Zero)
                    {
                        Marshal.WriteIntPtr(data, _systemDirAnsi);
                        DiagnosticLog.Write("ENV", $"GET_SYSTEM_DIRECTORY -> {_systemDirectory}");
                    }
                    else
                    {
                        DiagnosticLog.Write("ENV", "GET_SYSTEM_DIRECTORY -> BAŞARISIZ (null ptr)");
                    }
                    return true;
                }

            case RetroEnvironment.GET_SAVE_DIRECTORY:
                {
                    if (data != IntPtr.Zero && _saveDirAnsi != IntPtr.Zero)
                    {
                        Marshal.WriteIntPtr(data, _saveDirAnsi);
                        DiagnosticLog.Write("ENV", $"GET_SAVE_DIRECTORY -> {_saveDirectory}");
                    }
                    return true;
                }

            case RetroEnvironment.GET_CAN_DUPE:
                {
                    if (data != IntPtr.Zero)
                        Marshal.WriteByte(data, 1); // true
                    return true;
                }

            case RetroEnvironment.GET_VARIABLE:
                {
                    // Genesis Plus GX değişkenleri — varsayılanları döndür
                    if (data != IntPtr.Zero)
                    {
                        var variable = Marshal.PtrToStructure<RetroVariable>(data);
                        string? key = Marshal.PtrToStringAnsi(variable.Key);

                        string? value = key switch
                        {
                            // ──── Sistem ────
                            "genesis_plus_gx_system_hw" => "auto",
                            "genesis_plus_gx_region_detect" => "auto",
                            // KRİTİK: SEGA CD için BIOS MUTLAKA etkinleştirilmeli.
                            // "disabled" ise çekirdek BIOS vektörlerini başlatmaz → retro_load_game'de SIGSEGV.
                            "genesis_plus_gx_bios" => (CurrentConsoleType == ConsoleType.SegaCD) ? "enabled" : "disabled",
                            "genesis_plus_gx_system_bram" => "per bios",
                            "genesis_plus_gx_cart_size" => "disabled",
                            "genesis_plus_gx_cart_bram" => "per cart",
                            "genesis_plus_gx_force_dtack" => "enabled",
                            "genesis_plus_gx_addr_error" => "enabled",
                            "genesis_plus_gx_render" => "single field",
                            "genesis_plus_gx_frameskip" => "disabled",
                            "genesis_plus_gx_overclock" => "100%",
                            "genesis_plus_gx_no_sprite_limit" => "disabled",
                            "genesis_plus_gx_overscan" => "disabled",
                            "genesis_plus_gx_gg_extra" => "disabled",
                            "genesis_plus_gx_gun_cursor" => "no",
                            "genesis_plus_gx_invert_mouse" => "no",
                            "genesis_plus_gx_show_lightgun_crosshair" => "disabled",

                            // ──── Kontrolcü (6-Buton Desteği) ────
                            "genesis_plus_gx_sixb_autoset" => "enabled",
                            "genesis_plus_gx_input" => "6 button pad",
                            "picodrive_input1" => "6 button pad",
                            "picodrive_input2" => "6 button pad",
                            "picodrive_drc" => "enabled",
                            "picodrive_region" => "Auto",
                            "picodrive_audio_filter" => "disabled",
                            // PicoDrive SEGA CD BIOS değişkeni
                            "picodrive_cd_bios" => (CurrentConsoleType == ConsoleType.SegaCD) ? "enabled" : "disabled",
                            // PicoDrive CDDA ses hattı (44100Hz PCM)
                            "picodrive_sound_rate" => "44100",
                            "picodrive_sndfilter_quality" => "high",

                            // ──── Ses — KRİTİK: hiçbir ses değişkeni null döndürmemeli ────
                            "genesis_plus_gx_ym2612" => YDrive.Services.SettingsManager.Instance.Current.Ym2612Emulation,
                            "genesis_plus_gx_svp" => YDrive.Services.SettingsManager.Instance.Current.SvpSupport ? "enabled" : "disabled",
                            "genesis_plus_gx_audio_samplerate" => YDrive.Services.SettingsManager.Instance.Current.AudioSamplerate,
                            "genesis_plus_gx_ym2612_enhanced_vgm" => "enabled",

                            // YM2413 (OPLL / FM): "enabled" ile her ROM'da aktif olur
                            "genesis_plus_gx_ym2413" => "enabled",

                            // Stereo çıkış
                            "genesis_plus_gx_sound_output" => "stereo",

                            // Ses filtresi — devre dışı: filtre sesi sıfırlayabilir
                            "genesis_plus_gx_audio_filter" => "disabled",
                            "genesis_plus_gx_lowpass_range" => "60",

                            // Ses kanalları ön-kuvvetlendirici seviyeleri
                            // 100 = %100 (orijinal), 150 = %150 (daha yüksek)
                            "genesis_plus_gx_psg_preamp" => "150",
                            "genesis_plus_gx_fm_preamp" => "150",
                            "genesis_plus_gx_cdda_volume" => "100",
                            "genesis_plus_gx_pcm_volume" => "100",

                            // SMS/GG PSG türü
                            "genesis_plus_gx_psg_type" => "sg",

                            // DAC (YM2612 DAC bits)
                            "genesis_plus_gx_dac_bits" => "14",

                            _ => null
                        };

                        // Ses değişkenleri için özel critical log
                        bool isAudioKey = key != null &&
                                          (key.Contains("ym") || key.Contains("sound") ||
                                           key.Contains("preamp") || key.Contains("audio") ||
                                           key.Contains("psg") || key.Contains("dac"));

                        if (isAudioKey)
                            DiagnosticLog.Write("GET_VAR_AUDIO", $"KEY={key} → VALUE={value ?? "null (unhandled!)"}");
                        else
                            DiagnosticLog.Write("GET_VAR", $"Key: {key} → {value ?? "null"}");

                        if (value != null)
                        {
                            if (!_variablePtrCache.TryGetValue(value, out IntPtr pVal))
                            {
                                pVal = Marshal.StringToCoTaskMemUTF8(value);
                                _variablePtrCache[value] = pVal;
                            }
                            variable.Value = pVal;
                            Marshal.StructureToPtr(variable, data, false);
                            return true;
                        }
                    }
                    return false;
                }

            case RetroEnvironment.SET_VARIABLES:
            case RetroEnvironment.SET_CORE_OPTIONS_V2:
                return true;

            case RetroEnvironment.GET_VARIABLE_UPDATE:
                {
                    if (data != IntPtr.Zero)
                        Marshal.WriteByte(data, 0); // false — değişiklik yok
                    return true;
                }

            case RetroEnvironment.GET_LOG_INTERFACE:
                {
                    // ARM64 üzerinde Cdecl ve varargs (...) callback eşleşmekliği
                    // stack bozulmasına (SIGSEGV / Hang) neden olduğu için
                    // log arayüzünü kasıtlı olarak devredışı bırakıyoruz.
                    return false;
                }

            case RetroEnvironment.GET_AUDIO_VIDEO_ENABLE:
                {
                    if (data != IntPtr.Zero)
                    {
                        // Bit 0 = 1 (Video), Bit 1 = 2 (Audio) -> 1 | 2 = 3 (Hem video hem ses aktif!)
                        Marshal.WriteInt32(data, 3);
                        DiagnosticLog.Write("ENV", "GET_AUDIO_VIDEO_ENABLE → 3 (video+audio aktif)");
                    }
                    return true;
                }

            case 62: // SET_AUDIO_BUFFER_STATUS
                // Çekirdeğin kendi tampon denetimini frontend'e zorlamasını engelliyoruz
                return false;

            case RetroEnvironment.SET_SYSTEM_AV_INFO:
                {
                    if (data != IntPtr.Zero)
                    {
                        var avInfo = Marshal.PtrToStructure<RetroSystemAvInfo>(data);
                        OnSystemAvInfoChanged?.Invoke(avInfo);
                    }
                    return true;
                }

            case RetroEnvironment.SET_INPUT_DESCRIPTORS:
            case RetroEnvironment.SET_CONTROLLER_INFO:
            case RetroEnvironment.SET_SUBSYSTEM_INFO:
            case RetroEnvironment.SET_GEOMETRY:
                return true;

            case RetroEnvironment.GET_CORE_OPTIONS_VERSION:
                {
                    if (data != IntPtr.Zero)
                        Marshal.WriteInt32(data, 0); // v0
                    return true;
                }

            case RetroEnvironment.GET_INPUT_BITMASKS:
                return false; // desteklenmez

            default:
                System.Diagnostics.Debug.WriteLine($"[Libretro] Bilinmeyen environment komutu: {cmd}");
                return false;
        }
    }

    // ═══════════════════ Video Callback ═══════════════════

    private void VideoRefreshHandler(IntPtr data, uint width, uint height, nuint pitch)
    {
        if (data == IntPtr.Zero) return; // duped frame
        OnVideoFrame?.Invoke(data, width, height, pitch);
    }

    // ═══════════════════ Audio Callbacks ═══════════════════

    private unsafe void AudioSampleHandler(short left, short right)
    {
        // Allocation-free approach using stackalloc
        short* stereo = stackalloc short[2];
        stereo[0] = left;
        stereo[1] = right;

        OnAudioSampleBatch?.Invoke((IntPtr)stereo, 1);
    }

    private nuint AudioSampleBatchHandler(IntPtr data, nuint frames)
    {
        OnAudioSampleBatch?.Invoke(data, frames);
        return frames;
    }

    // ═══════════════════ Input Callbacks ═══════════════════

    private void InputPollHandler()
    {
        OnInputPoll?.Invoke();
    }

    private short InputStateHandler(uint port, uint device, uint index, uint id)
    {
        return OnInputState?.Invoke(port, device, index, id) ?? 0;
    }

    private void LogPrintfHandler(uint level, IntPtr fmt, IntPtr a1, IntPtr a2, IntPtr a3, IntPtr a4, IntPtr a5, IntPtr a6, IntPtr a7, IntPtr a8)
    {
        try
        {
            string? format = Marshal.PtrToStringAnsi(fmt);
            if (format != null)
            {
                // Unmanaged varargs için basit biçimlendirme simülatörü
                string formatted = FormatCStyle(format, a1, a2, a3, a4, a5, a6, a7, a8);

                var levelStr = level switch
                {
                    0 => "DEBUG",
                    1 => "INFO",
                    2 => "WARN",
                    3 => "ERROR",
                    _ => level.ToString()
                };
                DiagnosticLog.Write($"CORE_{levelStr}", formatted.TrimEnd('\n', '\r'));
            }
        }
        catch { }
    }

    private string FormatCStyle(string format, params IntPtr[] args)
    {
        try
        {
            int argIndex = 0;
            System.Text.StringBuilder sb = new();
            for (int i = 0; i < format.Length; i++)
            {
                if (format[i] == '%' && i + 1 < format.Length)
                {
                    char spec = format[i + 1];
                    if (spec == '%')
                    {
                        sb.Append('%');
                        i++;
                        continue;
                    }

                    if (argIndex >= args.Length)
                    {
                        sb.Append('%').Append(spec);
                        i++;
                        continue;
                    }

                    IntPtr arg = args[argIndex++];
                    if (spec == 'd' || spec == 'i')
                    {
                        sb.Append(arg.ToInt64());
                    }
                    else if (spec == 'u')
                    {
                        sb.Append((uint)arg.ToInt64());
                    }
                    else if (spec == 's')
                    {
                        string? s = Marshal.PtrToStringAnsi(arg);
                        sb.Append(s ?? "(null)");
                    }
                    else if (spec == 'p' || spec == 'x')
                    {
                        sb.Append("0x").Append(arg.ToString("X"));
                    }
                    else
                    {
                        sb.Append('%').Append(spec);
                    }
                    i++;
                }
                else
                {
                    sb.Append(format[i]);
                }
            }
            return sb.ToString();
        }
        catch
        {
            return format;
        }
    }
}


