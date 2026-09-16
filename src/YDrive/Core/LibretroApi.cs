// ─────────────────────────────────────────────────────────────
//  LibretroApi.cs — Libretro API fonksiyonlarına dinamik P/Invoke erişimi
//  NativeLibrary.Load ile DLL'i yükler, fonksiyon pointer'larını bağlar
// ─────────────────────────────────────────────────────────────

using System.Runtime.InteropServices;

namespace SegaEmulator.Core;

/// <summary>
/// Genesis Plus GX libretro çekirdeğinin C API fonksiyonlarını
/// dinamik olarak yükleyen ve çağrılabilir hale getiren sınıf.
/// </summary>
public sealed class LibretroApi : IDisposable
{
    private IntPtr _libraryHandle;
    private bool _disposed;

    // ───────────── Delegate tipleri (C fonksiyon imzaları) ─────────────

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroInitDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroDeinitDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate uint RetroApiVersionDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroGetSystemInfoDelegate(ref RetroSystemInfo info);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroGetSystemAvInfoDelegate(ref RetroSystemAvInfo info);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroSetEnvironmentDelegate(RetroEnvironmentDelegate cb);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroSetVideoRefreshDelegate(RetroVideoRefreshDelegate cb);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroSetAudioSampleDelegate(RetroAudioSampleDelegate cb);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroSetAudioSampleBatchDelegate(RetroAudioSampleBatchDelegate cb);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroSetInputPollDelegate(RetroInputPollDelegate cb);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroSetInputStateDelegate(RetroInputStateDelegate cb);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroSetControllerPortDeviceDelegate(uint port, uint device);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroResetDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroRunDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.U1)]
    public delegate bool RetroLoadGameDelegate(ref RetroGameInfo game);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void RetroUnloadGameDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate nuint RetroSerializeSizeDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.U1)]
    public delegate bool RetroSerializeDelegate(IntPtr data, nuint size);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.U1)]
    public delegate bool RetroUnserializeDelegate(IntPtr data, nuint size);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate IntPtr RetroGetMemoryDataDelegate(uint id);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate nuint RetroGetMemorySizeDelegate(uint id);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate uint RetroGetRegionDelegate();

    // ───────────── Fonksiyon referansları ─────────────

    public RetroInitDelegate?                    Init { get; private set; }
    public RetroDeinitDelegate?                  Deinit { get; private set; }
    public RetroApiVersionDelegate?              ApiVersion { get; private set; }
    public RetroGetSystemInfoDelegate?           GetSystemInfo { get; private set; }
    public RetroGetSystemAvInfoDelegate?         GetSystemAvInfo { get; private set; }
    public RetroSetEnvironmentDelegate?          SetEnvironment { get; private set; }
    public RetroSetVideoRefreshDelegate?         SetVideoRefresh { get; private set; }
    public RetroSetAudioSampleDelegate?          SetAudioSample { get; private set; }
    public RetroSetAudioSampleBatchDelegate?     SetAudioSampleBatch { get; private set; }
    public RetroSetInputPollDelegate?            SetInputPoll { get; private set; }
    public RetroSetInputStateDelegate?           SetInputState { get; private set; }
    public RetroSetControllerPortDeviceDelegate? SetControllerPortDevice { get; private set; }
    public RetroResetDelegate?                   Reset { get; private set; }
    public RetroRunDelegate?                     Run { get; private set; }
    public RetroLoadGameDelegate?                LoadGame { get; private set; }
    public RetroUnloadGameDelegate?              UnloadGame { get; private set; }
    public RetroSerializeSizeDelegate?           SerializeSize { get; private set; }
    public RetroSerializeDelegate?               Serialize { get; private set; }
    public RetroUnserializeDelegate?             Unserialize { get; private set; }
    public RetroGetMemoryDataDelegate?           GetMemoryData { get; private set; }
    public RetroGetMemorySizeDelegate?           GetMemorySize { get; private set; }
    public RetroGetRegionDelegate?               GetRegion { get; private set; }

    public bool IsLoaded => _libraryHandle != IntPtr.Zero;

    /// <summary>
    /// Belirtilen yoldan libretro çekirdeğini yükler.
    /// </summary>
    public void LoadCore(string dllPath)
    {
        if (IsLoaded)
            throw new InvalidOperationException("Çekirdek zaten yüklenmiş. Önce Dispose() çağırın.");

        // Bağımlılıkları (DLL'in yanındaki diğer DLL'ler) da arayabilmesi için parametre eklendi.
        _libraryHandle = NativeLibrary.Load(dllPath, typeof(LibretroApi).Assembly, 
            DllImportSearchPath.UseDllDirectoryForDependencies | DllImportSearchPath.ApplicationDirectory);

        // Tüm fonksiyon pointer'larını bağla
        Init                    = GetFunction<RetroInitDelegate>("retro_init");
        Deinit                  = GetFunction<RetroDeinitDelegate>("retro_deinit");
        ApiVersion              = GetFunction<RetroApiVersionDelegate>("retro_api_version");
        GetSystemInfo           = GetFunction<RetroGetSystemInfoDelegate>("retro_get_system_info");
        GetSystemAvInfo         = GetFunction<RetroGetSystemAvInfoDelegate>("retro_get_system_av_info");
        SetEnvironment          = GetFunction<RetroSetEnvironmentDelegate>("retro_set_environment");
        SetVideoRefresh         = GetFunction<RetroSetVideoRefreshDelegate>("retro_set_video_refresh");
        SetAudioSample          = GetFunction<RetroSetAudioSampleDelegate>("retro_set_audio_sample");
        SetAudioSampleBatch     = GetFunction<RetroSetAudioSampleBatchDelegate>("retro_set_audio_sample_batch");
        SetInputPoll            = GetFunction<RetroSetInputPollDelegate>("retro_set_input_poll");
        SetInputState           = GetFunction<RetroSetInputStateDelegate>("retro_set_input_state");
        SetControllerPortDevice = GetFunction<RetroSetControllerPortDeviceDelegate>("retro_set_controller_port_device");
        Reset                   = GetFunction<RetroResetDelegate>("retro_reset");
        Run                     = GetFunction<RetroRunDelegate>("retro_run");
        LoadGame                = GetFunction<RetroLoadGameDelegate>("retro_load_game");
        UnloadGame              = GetFunction<RetroUnloadGameDelegate>("retro_unload_game");
        SerializeSize           = GetFunction<RetroSerializeSizeDelegate>("retro_serialize_size");
        Serialize               = GetFunction<RetroSerializeDelegate>("retro_serialize");
        Unserialize             = GetFunction<RetroUnserializeDelegate>("retro_unserialize");
        GetMemoryData           = GetFunction<RetroGetMemoryDataDelegate>("retro_get_memory_data");
        GetMemorySize           = GetFunction<RetroGetMemorySizeDelegate>("retro_get_memory_size");
        GetRegion               = GetFunction<RetroGetRegionDelegate>("retro_get_region");
    }

    /// <summary>
    /// DLL'den belirtilen fonksiyon adını bulur ve delegate olarak döndürür.
    /// </summary>
    private T GetFunction<T>(string functionName) where T : Delegate
    {
        if (!NativeLibrary.TryGetExport(_libraryHandle, functionName, out IntPtr funcPtr))
            throw new EntryPointNotFoundException(
                $"Libretro çekirdeğinde '{functionName}' fonksiyonu bulunamadı.");

        return Marshal.GetDelegateForFunctionPointer<T>(funcPtr);
    }

    // ───────────── IDisposable ─────────────

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        if (_libraryHandle != IntPtr.Zero)
        {
            NativeLibrary.Free(_libraryHandle);
            _libraryHandle = IntPtr.Zero;
        }

        // Tüm referansları temizle
        Init = null; Deinit = null; ApiVersion = null;
        GetSystemInfo = null; GetSystemAvInfo = null;
        SetEnvironment = null; SetVideoRefresh = null;
        SetAudioSample = null; SetAudioSampleBatch = null;
        SetInputPoll = null; SetInputState = null;
        SetControllerPortDevice = null;
        Reset = null; Run = null;
        LoadGame = null; UnloadGame = null;
        SerializeSize = null; Serialize = null; Unserialize = null;
        GetMemoryData = null; GetMemorySize = null; GetRegion = null;
    }
}
