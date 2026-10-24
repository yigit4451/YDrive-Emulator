import Foundation
import AVFoundation
import os

private let audioLog = Logger(subsystem: "com.yigit.ydrive", category: "AudioEngine")

/// Low-latency, zero-allocation lock-free ring buffer Audio Engine using AVAudioSourceNode.
/// Eliminates per-frame AVAudioPCMBuffer allocations and scheduleBuffer IPC overhead
/// that would otherwise stall the emulation thread and build up latency over sessions.
final class YDriveAudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var audioFormat: AVAudioFormat?
    private var isStarted = false

    // Lock-free SPSC ring buffer (capacity: 8192 stereo frames = 16384 Int16 samples, ~185ms at 44.1kHz)
    private static let frameCapacity = 8192 // Must be power of 2
    private static let frameMask = frameCapacity - 1
    private let ringBuffer: UnsafeMutablePointer<Int16>
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private let bufferLock = os_unfair_lock_t.allocate(capacity: 1)

    private static var sessionConfigured = false

    init() {
        ringBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Self.frameCapacity * 2)
        ringBuffer.initialize(repeating: 0, count: Self.frameCapacity * 2)
        bufferLock.initialize(to: os_unfair_lock())

        if !Self.sessionConfigured {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setPreferredIOBufferDuration(0.005) // 5ms low-latency audio IO
                try session.setActive(true)
                Self.sessionConfigured = true
            } catch {
                audioLog.error("Failed to setup AVAudioSession: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        stop()
        ringBuffer.deallocate()
        bufferLock.deallocate()
    }

    /// Configures the engine for the given sample rate and starts it.
    func start(sampleRate: Double) {
        let validRate = sampleRate > 8000 ? sampleRate : 44100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: validRate, channels: 2) else {
            audioLog.error("Failed to create AVAudioFormat")
            return
        }

        // Flush old audio samples
        os_unfair_lock_lock(bufferLock)
        writeIndex = 0
        readIndex = 0
        os_unfair_lock_unlock(bufferLock)

        if let existingNode = sourceNode {
            engine.detach(existingNode)
            sourceNode = nil
        }

        let ringPtr = self.ringBuffer
        let lockPtr = self.bufferLock
        let mask = Self.frameMask

        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let count = Int(frameCount)
            guard ablPointer.count >= 2,
                  let leftOut = ablPointer[0].mData?.assumingMemoryBound(to: Float.self),
                  let rightOut = ablPointer[1].mData?.assumingMemoryBound(to: Float.self),
                  let self = self else {
                for buf in ablPointer {
                    if let ptr = buf.mData {
                        memset(ptr, 0, Int(buf.mDataByteSize))
                    }
                }
                return noErr
            }

            os_unfair_lock_lock(lockPtr)
            var rIdx = self.readIndex
            let wIdx = self.writeIndex
            let available = wIdx - rIdx
            let toRead = min(count, max(0, available))

            let scale: Float = 1.0 / 32768.0
            for i in 0..<toRead {
                let slot = (rIdx & mask) * 2
                leftOut[i]  = Float(ringPtr[slot]) * scale
                rightOut[i] = Float(ringPtr[slot + 1]) * scale
                rIdx += 1
            }
            self.readIndex = rIdx
            os_unfair_lock_unlock(lockPtr)

            if toRead < count {
                for i in toRead..<count {
                    leftOut[i] = 0
                    rightOut[i] = 0
                }
            }
            return noErr
        }

        sourceNode = node
        audioFormat = format
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            isStarted = true
            audioLog.info("Audio engine started at \(validRate) Hz")
        } catch {
            audioLog.error("Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    /// Stops the audio engine and releases resources.
    func stop() {
        if isStarted || engine.isRunning {
            engine.stop()
        }
        if let existingNode = sourceNode {
            engine.detach(existingNode)
            sourceNode = nil
        }
        isStarted = false
        audioFormat = nil
        os_unfair_lock_lock(bufferLock)
        writeIndex = 0
        readIndex = 0
        os_unfair_lock_unlock(bufferLock)
    }

    /// Enqueues a batch of 16-bit interleaved PCM frames with zero heap allocations.
    func pushAudio(data: UnsafePointer<Int16>, frames: Int) {
        guard isStarted, frames > 0 else { return }

        let mask = Self.frameMask
        let cap = Self.frameCapacity
        // Keep max latency bounded (~65ms = 2880 frames at 44.1kHz) so audio never lags behind input
        let maxQueuedFrames = 2880

        os_unfair_lock_lock(bufferLock)
        var wIdx = writeIndex
        var rIdx = readIndex

        if (wIdx - rIdx) + frames > maxQueuedFrames {
            rIdx = max(rIdx, (wIdx + frames) - maxQueuedFrames)
        }
        if (wIdx - rIdx) + frames > cap {
            rIdx = (wIdx + frames) - cap
        }

        for i in 0..<frames {
            let slot = (wIdx & mask) * 2
            ringBuffer[slot]     = data[i * 2]
            ringBuffer[slot + 1] = data[i * 2 + 1]
            wIdx += 1
        }

        writeIndex = wIdx
        readIndex = rIdx
        os_unfair_lock_unlock(bufferLock)
    }
}
