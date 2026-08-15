// ─────────────────────────────────────────────────────────────
//  DiagnosticLog.cs — Dosyaya tanılama günlüğü yazar
//  Debug.WriteLine yerine dosyaya yazarak her ortamda çalışır
// ─────────────────────────────────────────────────────────────

using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;

namespace SegaEmulator;

/// <summary>
/// Thread-safe dosya tabanlı tanılama günlüğü.
/// Uygulama kapanırken FlushAndClose() çağrılmalıdır.
/// </summary>
public static class DiagnosticLog
{
    private static readonly ConcurrentQueue<string> _queue = new();
    private static readonly Timer _flushTimer;
    private static readonly object _writeLock = new();
    private static readonly Stopwatch _sessionTimer = Stopwatch.StartNew();

    // ──── Log dosyası yolu — dışarıdan okunabilir ────
    public static string LogPath { get; }

    static DiagnosticLog()
    {
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YDrive", "logs");
        try { Directory.CreateDirectory(dir); } catch { }
        LogPath = Path.Combine(dir, $"diag_{DateTime.Now:yyyyMMdd_HHmmss}.log");

        // Her 500 ms'de bir kuyruktan dosyaya yaz
        _flushTimer = new Timer(_ => Flush(), null, 500, 500);

        Write("SYSTEM", $"═══════════════════════════════════════");
        Write("SYSTEM", $"YDrive — Oturum Başladı");
        Write("SYSTEM", $"Zaman       : {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        Write("SYSTEM", $"Log Dosyası : {LogPath}");
        Write("SYSTEM", $"OS          : {Environment.OSVersion}");
        Write("SYSTEM", $"64-bit      : {Environment.Is64BitProcess}");
        Write("SYSTEM", $".NET Sürümü : {Environment.Version}");
        Write("SYSTEM", $"═══════════════════════════════════════");

        Console.WriteLine($"[DiagnosticLog] Log dosyası: {LogPath}");
    }

    // ═══════════════════ Yazma API'si ═══════════════════

    /// <summary>
    /// Kuyruğa yeni bir log satırı ekler.
    /// Her thread'den güvenle çağrılabilir.
    /// </summary>
    public static void Write(string tag, string message)
    {
        string elapsed = "+" + _sessionTimer.Elapsed.ToString(@"mm\:ss\.fff");
        string line = $"[{DateTime.Now:HH:mm:ss.fff}] {elapsed} [{tag,-12}] {message}";
        _queue.Enqueue(line);
    }

    /// <summary>
    /// Kritik hata — kuyruğa ekler ve hemen diske yazar.
    /// Performans gerektirmeyen hata yollarında kullanılır.
    /// </summary>
    public static void WriteError(string tag, string message)
    {
        Write($"ERROR/{tag}", message);
        Flush(); // anında diske flush
    }

    // ═══════════════════ Oturum Özeti ═══════════════════

    /// <summary>
    /// Oturum sonu istatistiklerini log'a yazar.
    /// Dispose veya kapanış akışında çağrılmalıdır.
    /// </summary>
    public static void WriteSessionSummary(string extraInfo = "")
    {
        Write("SYSTEM", $"═══════════════════════════════════════");
        Write("SYSTEM", $"Oturum Sonu — Toplam Süre: " + _sessionTimer.Elapsed.ToString(@"hh\:mm\:ss\.fff"));
        if (!string.IsNullOrWhiteSpace(extraInfo))
            Write("SYSTEM", extraInfo);
        Write("SYSTEM", $"═══════════════════════════════════════");
    }

    // ═══════════════════ Flush / Kapat ═══════════════════

    private static void Flush()
    {
        if (_queue.IsEmpty) return;

        var lines = new List<string>();
        while (_queue.TryDequeue(out string? line))
            lines.Add(line!);

        if (lines.Count == 0) return;

        lock (_writeLock)
        {
            try { File.AppendAllLines(LogPath, lines); }
            catch { /* Dosya yazma hatası görmezden gel */ }
        }
    }

    /// <summary>
    /// Uygulamanın kapanışında çağrılmalıdır.
    /// Kuyruktaki tüm mesajları diske yazar ve timer'ı durdurur.
    /// </summary>
    public static void FlushAndClose()
    {
        _flushTimer.Change(Timeout.Infinite, Timeout.Infinite); // yeni tetiklenmeyi engelle
        Flush();           // kalan mesajları yaz
        _flushTimer.Dispose();
    }
}
