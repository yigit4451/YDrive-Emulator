// ─────────────────────────────────────────────────────────────
//  AudioManager.cs — NAudio ile düşük gecikmeli ses çıkışı
//  BufferedWaveProvider + WaveOutEvent, Libretro PCM → NAudio akışı
//
//  Thread modeli:
//    • Initialize()   → herhangi bir thread (lock korumalı)
//    • WriteSamples() → emülasyon thread'i (lock-free hot path)
//    • Pause/Resume   → UI thread
// ─────────────────────────────────────────────────────────────

using System.Runtime.InteropServices;
using NAudio.Wave;

namespace SegaEmulator.Audio;

/// <summary>
/// Libretro çekirdeğinden gelen stereo 16-bit PCM ses verilerini
/// NAudio üzerinden düşük gecikmeyle çalar.
/// </summary>
public class AudioManager : IDisposable
{
    // ──── Donanım nesneleri (lock ile korunur) ────
    private readonly object _lock = new();
    private IWavePlayer?          _waveOut;
    private BufferedWaveProvider? _bufferedProvider;

    // ──── Durum (volatile: emülasyon thread'inden okunur) ────
    private volatile bool _initialized;
    private volatile bool _disposed;
    private float _volume = 1.0f;  // Tam ses — WaveOutEvent sistem sesini değiştirmez

    // ──── Tanı sayaçları ────
    private long _writeCallCount;
    private long _totalFramesWritten;
    private long _nonZeroCallCount;

    /// <summary>Yazılımsal ses seviyesi (0.0 – 1.0). Thread-safe.</summary>
    public float Volume
    {
        get => _volume;
        set => _volume = Math.Clamp(value, 0f, 1f);
    }

    public bool IsPlaying
    {
        get { lock (_lock) return _waveOut?.PlaybackState == PlaybackState.Playing; }
    }

    // ═══════════════════ Başlatma ═══════════════════

    /// <summary>
    /// Ses çıkışını belirtilen örnekleme hızıyla başlatır.
    /// Herhangi bir thread'den çağrılabilir; lock ile korunur.
    /// </summary>
    public void Initialize(double sampleRate)
    {
        if (_disposed) return;

        int rate = (int)sampleRate;
        if (rate <= 0 || rate > 192000)
        {
            DiagnosticLog.Write("AUDIO", $"⚠ Geçersiz sampleRate={sampleRate} → 44100 kullanılıyor");
            rate = 44100;
        }

        DiagnosticLog.Write("AUDIO", $"══ Initialize sampleRate={rate} ══");

        lock (_lock)
        {
            ShutdownLocked();

            // Stereo, 16-bit PCM (her stereo frame = 4 byte)
            var waveFormat = new WaveFormat(rate, 16, 2);

            // ~2 saniyelik tampon
            int bufLen = rate * 4 * 2;

            _bufferedProvider = new BufferedWaveProvider(waveFormat)
            {
                BufferLength            = bufLen,
                DiscardOnBufferOverflow = true,
                // ReadFully = false: tampon boşken sıfır gönderme, direkt underrun kabul et
                ReadFully               = false
            };

            DiagnosticLog.Write("AUDIO",
                $"BufferedWaveProvider: {waveFormat.SampleRate}Hz {waveFormat.BitsPerSample}bit " +
                $"{waveFormat.Channels}ch, bufLen={bufLen}");

            try
            {
                var wo = new WaveOutEvent { DesiredLatency = 80, NumberOfBuffers = 3 };
                wo.Init(_bufferedProvider);
                _waveOut = wo;
                _waveOut.Play();
                _initialized = true;
                DiagnosticLog.Write("AUDIO",
                    $"✓ WaveOutEvent başlatıldı, PlaybackState={_waveOut.PlaybackState}");
            }
            catch (Exception ex)
            {
                DiagnosticLog.Write("AUDIO", $"✗ WaveOutEvent: {ex.Message} → WasapiOut deneniyor");
                try
                {
                    _waveOut?.Dispose();
                    var wasapi = new WasapiOut(
                        NAudio.CoreAudioApi.AudioClientShareMode.Shared, 80);
                    wasapi.Init(_bufferedProvider);
                    _waveOut = wasapi;
                    _waveOut.Play();
                    _initialized = true;
                    DiagnosticLog.Write("AUDIO",
                        $"✓ WasapiOut başlatıldı, PlaybackState={_waveOut.PlaybackState}");
                }
                catch (Exception ex2)
                {
                    DiagnosticLog.Write("AUDIO", $"✗ WasapiOut de başarısız: {ex2.Message}");
                    _waveOut = null;
                    _initialized = false;
                }
            }

            // ── Volume sağlık kontrolü: sıfır sessizliğe neden olur ──
            if (_volume < 0.001f)
            {
                DiagnosticLog.Write("AUDIO", $"⚠ Volume {_volume:F3} sıfıra çok yakın! 1.0 olarak düzeltiliyor.");
                _volume = 1.0f;
            }
            DiagnosticLog.Write("AUDIO", $"Volume başlangıç seviyesi: {_volume:F3}");

            _writeCallCount     = 0;
            _totalFramesWritten = 0;
            _nonZeroCallCount   = 0;
        }
    }

    // ═══════════════════ Ses Yazma — Hot Path ═══════════════════

    /// <summary>
    /// Libretro retro_audio_sample_batch callback'inden çağrılır.
    /// data: interleaved stereo short* (L0 R0 L1 R1 … Ln Rn)
    /// frames: stereo frame sayısı
    /// </summary>
    public void WriteSamples(IntPtr data, nuint frames)
    {
        // volatile okuma — lock almadan hızlı çıkış
        if (!_initialized) return;
        if (data == IntPtr.Zero || frames == 0) return;

        // ── Boyut hesabı ──────────────────────────────────────────────
        // Stereo interleaved: L0 R0 L1 R1 … her frame = 2 short = 4 byte
        int sampleCount = (int)frames * 2;   // toplam short sayısı
        int byteCount   = sampleCount * 2;   // toplam byte sayısı

        if (sampleCount <= 0 || sampleCount > 96000) return;  // anlamsız büyük batch koru

        // ── Tanılama sayacı ───────────────────────────────────────────
        long n = System.Threading.Interlocked.Increment(ref _writeCallCount);

        // ── Ham byte ön-kontrolü (ilk 10 çağrı) ──────────────────────
        // rawNonZero = false ise sorun C#'ta değil, çekirdektedir.
        if (n <= 10)
        {
            int rawCheck = Math.Min(byteCount, 32);
            byte[] rawBytes = new byte[rawCheck];
            Marshal.Copy(data, rawBytes, 0, rawCheck);
            bool rawNz = System.Array.Exists(rawBytes, b => b != 0);
            string rawHex = BitConverter.ToString(rawBytes);
            DiagnosticLog.Write("AUDIO_RAW",
                $"WriteSamples #{n}: frames={frames}, rawNonZero={rawNz}, rawHex={rawHex}");
        }

        // ── ADIM 1: IntPtr → short[] (Marshal.Copy ile doğrudan kopyala) ──
        short[] pcmSamples = new short[sampleCount];
        Marshal.Copy(data, pcmSamples, 0, sampleCount);

        // ── ADIM 2: Yazılımsal ses çarpımı ───────────────────────────
        float vol = _volume;
        bool hasNonZero = false;

        for (int i = 0; i < sampleCount; i++)
        {
            short v = pcmSamples[i];
            if (v != 0) hasNonZero = true;
            if (vol < 0.999f)
                pcmSamples[i] = (short)Math.Clamp((int)(v * vol), short.MinValue, short.MaxValue);
        }

        // ── ADIM 3: short[] → byte[] → NAudio BufferedWaveProvider ──
        byte[] byteBuffer = new byte[byteCount];
        Buffer.BlockCopy(pcmSamples, 0, byteBuffer, 0, byteBuffer.Length);

        var provider = _bufferedProvider;
        if (provider == null) return;   // Initialize() henüz tamamlanmadı
        provider.AddSamples(byteBuffer, 0, byteBuffer.Length);

        // ── WaveOut durduysa yeniden başlat ──────────────────────────
        var wo = _waveOut;
        if (wo != null && wo.PlaybackState == PlaybackState.Stopped)
        {
            wo.Play();
            DiagnosticLog.Write("AUDIO", "⚡ WaveOut durmuştu → Play() çağrıldı");
        }

        // ── Tanılama ─────────────────────────────────────────────────
        System.Threading.Interlocked.Add(ref _totalFramesWritten, (long)frames);
        if (hasNonZero) System.Threading.Interlocked.Increment(ref _nonZeroCallCount);

        if (n <= 10)
        {
            string hex = BitConverter.ToString(byteBuffer, 0, Math.Min(16, byteCount));
            DiagnosticLog.Write("AUDIO",
                $"WriteSamples #{n}: frames={frames}, sampleCount={sampleCount}, " +
                $"nonZero={hasNonZero}, hex={hex}, volume={vol:F2}, " +
                $"buffered={provider.BufferedBytes}, playState={_waveOut?.PlaybackState}");
        }
        else if ((n % 180) == 0)
        {
            DiagnosticLog.Write("AUDIO",
                $"WriteSamples #{n}: totalFrames={_totalFramesWritten}, " +
                $"nonZero={_nonZeroCallCount}/{n}, " +
                $"buffered={provider.BufferedBytes}, playState={_waveOut?.PlaybackState}");
        }
    }

    // ═══════════════════ Kontrol ═══════════════════

    public void Pause()
    {
        lock (_lock)
        {
            try { if (_waveOut?.PlaybackState == PlaybackState.Playing) _waveOut.Pause(); }
            catch (Exception ex) { DiagnosticLog.Write("AUDIO", $"Pause hatası: {ex.Message}"); }
        }
    }

    public void Resume()
    {
        lock (_lock)
        {
            try { if (_waveOut?.PlaybackState == PlaybackState.Paused) _waveOut.Play(); }
            catch (Exception ex) { DiagnosticLog.Write("AUDIO", $"Resume hatası: {ex.Message}"); }
        }
    }

    public void ClearBuffer()
    {
        lock (_lock) { _bufferedProvider?.ClearBuffer(); }
    }

    // ═══════════════════ Dahili Kapatma ═══════════════════

    /// <summary>_lock alınmış durumdayken çağrılır.</summary>
    private void ShutdownLocked()
    {
        _initialized = false;
        if (_waveOut != null)
        {
            try
            {
                DiagnosticLog.Write("AUDIO", $"Shutdown, PlaybackState={_waveOut.PlaybackState}");
                _waveOut.Stop();
                _waveOut.Dispose();
            }
            catch (Exception ex) { DiagnosticLog.Write("AUDIO", $"Shutdown hatası: {ex.Message}"); }
            _waveOut = null;
        }
        _bufferedProvider = null;
    }

    // ═══════════════════ IDisposable ═══════════════════

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        DiagnosticLog.Write("AUDIO",
            $"Dispose — calls={_writeCallCount}, frames={_totalFramesWritten}, nonZero={_nonZeroCallCount}");
        lock (_lock) { ShutdownLocked(); }
        GC.SuppressFinalize(this);
    }
}
