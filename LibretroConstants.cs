// ─────────────────────────────────────────────────────────────
//  LibretroConstants.cs — Libretro API sabitleri, enum ve struct tanımları
//  Genesis Plus GX çekirdeği ile iletişim için gerekli tüm sabitler
// ─────────────────────────────────────────────────────────────

using System.Runtime.InteropServices;

namespace SegaEmulator.Core;

/// <summary>
/// Libretro ortam callback komut sabitleri.
/// </summary>
public static class RetroEnvironment
{
    public const uint SET_ROTATION = 1;
    public const uint GET_OVERSCAN = 2;
    public const uint GET_CAN_DUPE = 3;
    public const uint SET_MESSAGE = 6;
    public const uint SHUTDOWN = 7;
    public const uint SET_PERFORMANCE_LEVEL = 8;
    public const uint GET_SYSTEM_DIRECTORY = 9;
    public const uint SET_PIXEL_FORMAT = 10;
    public const uint SET_INPUT_DESCRIPTORS = 11;
    public const uint SET_KEYBOARD_CALLBACK = 12;
    public const uint GET_VARIABLE = 15;
    public const uint SET_VARIABLES = 16;
    public const uint GET_VARIABLE_UPDATE = 17;
    public const uint SET_SUPPORT_NO_GAME = 18;
    public const uint GET_LIBRETRO_PATH = 19;
    public const uint GET_LOG_INTERFACE = 27;
    public const uint GET_SAVE_DIRECTORY = 31;
    public const uint SET_SYSTEM_AV_INFO = 32;
    public const uint SET_SUBSYSTEM_INFO = 34;
    public const uint SET_CONTROLLER_INFO = 35;
    public const uint SET_GEOMETRY = 37;
    public const uint GET_AUDIO_VIDEO_ENABLE = 47;
    public const uint GET_CORE_OPTIONS_VERSION = 52;
    public const uint SET_CORE_OPTIONS_V2 = 67;
    public const uint GET_INPUT_BITMASKS = 52 | 0x10000; // experimental
}

/// <summary>
/// Piksel format seçenekleri.
/// </summary>
public enum RetroPixelFormat : uint
{
    /// <summary>15-bit renk (eski, önerilmez)</summary>
    Format0RGB1555 = 0,
    /// <summary>32-bit XRGB8888 — modern tercih</summary>
    FormatXRGB8888 = 1,
    /// <summary>16-bit RGB565</summary>
    FormatRGB565 = 2
}

/// <summary>
/// Cihaz tipleri.
/// </summary>
public static class RetroDevice
{
    public const uint NONE = 0;
    public const uint JOYPAD = 1;
    public const uint MOUSE = 2;
    public const uint KEYBOARD = 3;
    public const uint LIGHTGUN = 4;
    public const uint ANALOG = 5;
    public const uint POINTER = 6;
}

/// <summary>
/// Joypad buton ID'leri — SEGA pad mapping için kullanılır.
/// </summary>
public enum RetroJoypadButton : uint
{
    B = 0,
    Y = 1,
    Select = 2,
    Start = 3,
    Up = 4,
    Down = 5,
    Left = 6,
    Right = 7,
    A = 8,
    X = 9,
    L = 10,
    R = 11,
    L2 = 12,
    R2 = 13,
    L3 = 14,
    R3 = 15
}

/// <summary>
/// Bölge sabitleri.
/// </summary>
public static class RetroRegion
{
    public const uint NTSC = 0;
    public const uint PAL = 1;
}

/// <summary>
/// Bellek tipleri.
/// </summary>
public static class RetroMemory
{
    public const uint SAVE_RAM = 0;
    public const uint RTC = 1;
    public const uint SYSTEM_RAM = 2;
    public const uint VIDEO_RAM = 3;
}

// ─────────────────────── Interop Struct'lar ───────────────────────

/// <summary>
/// Çekirdek hakkında temel bilgiler (ad, versiyon, uzantılar).
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct RetroSystemInfo
{
    public IntPtr LibraryName;
    public IntPtr LibraryVersion;
    public IntPtr ValidExtensions;
    [MarshalAs(UnmanagedType.U1)]
    public bool NeedFullpath;
    [MarshalAs(UnmanagedType.U1)]
    public bool BlockExtract;
}

/// <summary>
/// Oyun geometri bilgisi (çözünürlük, en-boy oranı).
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct RetroGameGeometry
{
    public uint BaseWidth;
    public uint BaseHeight;
    public uint MaxWidth;
    public uint MaxHeight;
    public float AspectRatio;
}

/// <summary>
/// Zamanlama bilgisi (FPS, örnekleme hızı).
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct RetroSystemTiming
{
    public double Fps;
    public double SampleRate;
}

/// <summary>
/// Ses ve video bilgisi yapısı (C ABI 64-bit hizalamasına uygun explicit layout).
/// </summary>
[StructLayout(LayoutKind.Explicit, Size = 40)]
public struct RetroSystemAvInfo
{
    [FieldOffset(0)]
    public RetroGameGeometry Geometry;

    [FieldOffset(24)]
    public RetroSystemTiming Timing;
}

/// <summary>
/// ROM yükleme için oyun bilgisi yapısı.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct RetroGameInfo
{
    public IntPtr Path;
    public IntPtr Data;
    public nuint Size;
    public IntPtr Meta;
}

/// <summary>
/// Çekirdek değişken yapısı (key-value).
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct RetroVariable
{
    public IntPtr Key;
    public IntPtr Value;
}

/// <summary>
/// Log seviyesi enum'u.
/// </summary>
public enum RetroLogLevel : uint
{
    Debug = 0,
    Info = 1,
    Warn = 2,
    Error = 3
}

// ─────────────────────── Callback Delegate Tipleri ───────────────────────

/// <summary>Ortam callback'i: çekirdek → frontend iletişim</summary>
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate bool RetroEnvironmentDelegate(uint cmd, IntPtr data);

/// <summary>Video yenileme callback'i: frame buffer gönderir</summary>
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate void RetroVideoRefreshDelegate(IntPtr data, uint width, uint height, nuint pitch);

/// <summary>Tek ses örneği callback'i</summary>
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate void RetroAudioSampleDelegate(short left, short right);

/// <summary>Toplu ses örneği callback'i — daha verimli</summary>
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate nuint RetroAudioSampleBatchDelegate(IntPtr data, nuint frames);

/// <summary>Input yoklama callback'i — her frame çağrılır</summary>
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate void RetroInputPollDelegate();

/// <summary>Input durum callback'i — buton basılı mı sorgular</summary>
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate short RetroInputStateDelegate(uint port, uint device, uint index, uint id);

[StructLayout(LayoutKind.Sequential)]
public struct RetroLogCallback
{
    public IntPtr Log;
}

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate void RetroLogPrintfDelegate(uint level, IntPtr fmt, IntPtr a1, IntPtr a2, IntPtr a3, IntPtr a4, IntPtr a5, IntPtr a6, IntPtr a7, IntPtr a8);
