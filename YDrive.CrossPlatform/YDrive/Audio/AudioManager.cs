using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Collections.Concurrent;
using System.Buffers;

namespace YDrive.Audio;

public class AudioManager : IDisposable
{
    private Thread? _playbackThread;
    private volatile bool _running;
    private volatile bool _paused;
    private readonly ConcurrentQueue<(byte[] Buffer, int Length)> _audioQueue = new();
    private double _sampleRate = 44100;
    private int _bufferSizeBytes = 4096;
    private readonly object _lock = new();

    // Platform audio output (set by platform-specific code)
    public Action<byte[], int, int>? PlatformWrite { get; set; }
    public Action<double>? PlatformInit { get; set; }
    public Action? PlatformPause { get; set; }
    public Action? PlatformResume { get; set; }
    public Action? PlatformStop { get; set; }

    public float Volume { get; set; } = 1.0f;
    public bool IsPlaying => _running && !_paused;

    public void Initialize(double sampleRate)
    {
        if (sampleRate <= 0 || sampleRate > 192000)
            sampleRate = 44100;

        _sampleRate = sampleRate;
        _bufferSizeBytes = (int)(sampleRate * 4 / 15); // ~66ms buffer (stereo 16-bit)

        PlatformInit?.Invoke(sampleRate);

        _running = true;
        _paused = false;
        _playbackThread = new Thread(PlaybackLoop)
        {
            Name = "AudioPlayback",
            IsBackground = true,
            Priority = ThreadPriority.AboveNormal
        };
        _playbackThread.Start();
    }

    public void WriteSamples(IntPtr data, nuint frames)
    {
        if (data == IntPtr.Zero || frames == 0 || !_running || _paused) return;

        int byteCount = (int)frames * 4; // stereo 16-bit = 4 bytes per frame
        byte[] buffer = ArrayPool<byte>.Shared.Rent(byteCount);
        Marshal.Copy(data, buffer, 0, byteCount);

        // Apply volume
        if (Volume < 0.99f)
        {
            ApplyVolume(buffer, byteCount, Volume);
        }

        // Drop oldest if queue too large (prevents latency buildup)
        while (_audioQueue.Count > 8)
        {
            if (_audioQueue.TryDequeue(out var oldItem))
            {
                ArrayPool<byte>.Shared.Return(oldItem.Buffer);
            }
        }

        _audioQueue.Enqueue((buffer, byteCount));
    }

    private void PlaybackLoop()
    {
        while (_running)
        {
            if (_paused)
            {
                Thread.Sleep(10);
                continue;
            }

            if (_audioQueue.TryDequeue(out var item))
            {
                try
                {
                    PlatformWrite?.Invoke(item.Buffer, 0, item.Length);
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[Audio] Write error: {ex.Message}");
                }
                finally
                {
                    ArrayPool<byte>.Shared.Return(item.Buffer);
                }
            }
            else
            {
                Thread.Sleep(1); // No data, yield briefly
            }
        }
    }

    private static void ApplyVolume(byte[] buffer, int length, float volume)
    {
        for (int i = 0; i < length - 1; i += 2)
        {
            short sample = (short)(buffer[i] | (buffer[i + 1] << 8));
            sample = (short)(sample * volume);
            buffer[i] = (byte)(sample & 0xFF);
            buffer[i + 1] = (byte)((sample >> 8) & 0xFF);
        }
    }

    public void Pause()
    {
        _paused = true;
        PlatformPause?.Invoke();
    }

    public void Resume()
    {
        _paused = false;
        PlatformResume?.Invoke();
    }

    public void ClearBuffer()
    {
        while (_audioQueue.TryDequeue(out var item)) 
        {
            ArrayPool<byte>.Shared.Return(item.Buffer);
        }
    }

    public void Dispose()
    {
        _running = false;
        _playbackThread?.Join(1000);
        _playbackThread = null;
        ClearBuffer();
        PlatformStop?.Invoke();
    }
}
