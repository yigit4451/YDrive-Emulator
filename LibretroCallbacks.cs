// ─────────────────────────────────────────────────────────────
//  LibretroCallbacks.cs — Çekirdek callback yönetimi
//  Video, ses, input ve environment callback'lerini yönetir
// ─────────────────────────────────────────────────────────────

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace SegaEmulator.Core;

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
    private string _systemDirectory = string.Empty;
    private string _saveDirectory = string.Empty;
    private GCHandle _systemDirHandle;
    private GCHandle _saveDirHandle;
    private bool _systemDirPinned;
    private bool _saveDirPinned;

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

    private void RefreshSystemDirPin()
    {
        if (_systemDirPinned) { _systemDirHandle.Free(); _systemDirPinned = false; }
        // Trailing slash EKLEME: fill_pathname_join() kendi ayracını ekler.
        // Trailing slash varsa kaldır, yoksa olduğu gibi bırak.
        string dir = _systemDirectory.TrimEnd(Path.DirectorySeparatorChar, '/');
        byte[] bytes = Encoding.UTF8.GetBytes(dir + "\0");
        _systemDirHandle = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        _systemDirPinned = true;
    }

    private void RefreshSaveDirPin()
    {
        if (_saveDirPinned) { _saveDirHandle.Free(); _saveDirPinned = false; }
        // Trailing slash EKLEME: fill_pathname_join() kendi ayracını ekler.
        string dir = _saveDirectory.TrimEnd(Path.DirectorySeparatorChar, '/');
        byte[] bytes = Encoding.UTF8.GetBytes(dir + "\0");
        _saveDirHandle = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        _saveDirPinned = true;
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
                    if (data != IntPtr.Zero && _systemDirPinned)
                    {
                        // UTF-8 null-terminated byte dizisinin pin'li adresini yaz;
                        // Türkçe karakterler (ğ, ş, İ) C++ tarafında doğru okunur.
                        Marshal.WriteIntPtr(data, _systemDirHandle.AddrOfPinnedObject());
                    }
                    return true;
                }

            case RetroEnvironment.GET_SAVE_DIRECTORY:
                {
                    if (data != IntPtr.Zero && _saveDirPinned)
                    {
                        // UTF-8 null-terminated byte dizisinin pin'li adresini yaz;
                        // Türkçe karakterler C++ tarafında doğru okunur.
                        Marshal.WriteIntPtr(data, _saveDirHandle.AddrOfPinnedObject());
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
                            "genesis_plus_gx_bios" => "disabled",
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

                            // ──── Ses — KRİTİK: hiçbir ses değişkeni null döndürmemeli ────
                            "genesis_plus_gx_ym2612" => SegaEmulator.Services.SettingsManager.Instance.Current.Ym2612Emulation,
                            "genesis_plus_gx_sixb_autoset" => SegaEmulator.Services.SettingsManager.Instance.Current.SixButtonAuto ? "enabled" : "disabled",
                            "genesis_plus_gx_svp" => SegaEmulator.Services.SettingsManager.Instance.Current.SvpSupport ? "enabled" : "disabled",
                            "genesis_plus_gx_audio_samplerate" => SegaEmulator.Services.SettingsManager.Instance.Current.AudioSamplerate,
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
                            variable.Value = Marshal.StringToCoTaskMemUTF8(value);
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
                    if (data != IntPtr.Zero && _logPrintfCallback != null)
                    {
                        var cb = new RetroLogCallback
                        {
                            Log = Marshal.GetFunctionPointerForDelegate(_logPrintfCallback)
                        };
                        Marshal.StructureToPtr(cb, data, false);
                        DiagnosticLog.Write("ENV", "GET_LOG_INTERFACE → log callback kaydedildi");
                        return true;
                    }
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

    private long _audioSampleCallCount;
    private long _audioBatchCallCount;

    private void AudioSampleHandler(short left, short right)
    {
        _audioSampleCallCount++;
        if (_audioSampleCallCount <= 5)
            DiagnosticLog.Write("CALLBACK", $"AudioSample #{_audioSampleCallCount}: L={left}, R={right}");

        // stackalloc yerine managed short[] kullanıyoruz:
        // stackalloc pointer'ı delegate çağrısı döndükten sonra geçersiz olabilir.
        // short[] pinlenip Marshal.Copy ile güvenle okunur.
        short[] stereo = new short[2] { left, right };
        byte[] bytes = new byte[4];              // 2 short × 2 byte = 4 byte
        Buffer.BlockCopy(stereo, 0, bytes, 0, 4);

        // byte[] pinle ve pointer olarak geçir
        var handle = System.Runtime.InteropServices.GCHandle.Alloc(bytes,
            System.Runtime.InteropServices.GCHandleType.Pinned);
        try
        {
            OnAudioSampleBatch?.Invoke(handle.AddrOfPinnedObject(), 1);
        }
        finally
        {
            handle.Free();
        }
    }

    private nuint AudioSampleBatchHandler(IntPtr data, nuint frames)
    {
        _audioBatchCallCount++;

        // ── İlk 5 çağrıda raw-byte dump: pointer'dan okunan gerçek PCM verisini doğrula ──
        // Eğer burada da hex=00-00... ise sorun çekirdektedir (C# okuma hatası değil).
        if (_audioBatchCallCount <= 5 || (_audioBatchCallCount <= 30 && _audioBatchCallCount % 5 == 0))
        {
            int sampleCount = (int)frames * 2; // stereo short sayısı
            int checkBytes = Math.Min(sampleCount * 2, 32); // en fazla 32 ham byte kontrol et

            if (data != IntPtr.Zero && checkBytes > 0)
            {
                byte[] rawBytes = new byte[checkBytes];
                Marshal.Copy(data, rawBytes, 0, checkBytes);
                bool rawNonZero = System.Array.Exists(rawBytes, b => b != 0);
                string rawHex = BitConverter.ToString(rawBytes);
                DiagnosticLog.Write("BATCH_RAW",
                    $"#{_audioBatchCallCount}: frames={frames}, rawNonZero={rawNonZero}, hex={rawHex}, " +
                    $"ptr=0x{data:X}, subscribers={OnAudioSampleBatch?.GetInvocationList().Length ?? 0}");
            }
            else
            {
                DiagnosticLog.Write("BATCH_RAW",
                    $"#{_audioBatchCallCount}: frames={frames}, data=NULL veya empty");
            }
        }
        else if ((_audioBatchCallCount % 60) == 0)
        {
            DiagnosticLog.Write("CALLBACK", $"AudioBatch #{_audioBatchCallCount}: totalSingle={_audioSampleCallCount}, totalBatch={_audioBatchCallCount}");
        }

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
