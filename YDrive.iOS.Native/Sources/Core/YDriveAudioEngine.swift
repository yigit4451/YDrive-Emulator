import Foundation
import AVFoundation
import os

private let audioLog = Logger(subsystem: "com.yigit.ydrive", category: "AudioEngine")

/// Thread-safe lock-free/spin-locked SPSC ring buffer for 16-bit stereo PCM audio.
private final class AudioRingBuffer: @unchecked Sendable {
    static let frameCapacity = 8192 // Power of 2 (~185ms at 44.1kHz)
    static let frameMask = frameCapacity - 1
    // Max queued frames (~65ms at 44.1kHz) so audio never lags behind input
    static let maxQueuedFrames = 2880

    private let lock = NSLock()
    private let samples: UnsafeMutablePointer<Int16>
    private var writeIndex: Int = 0
    private var readIndex: Int = 0

    init() {
        samples = UnsafeMutablePointer<Int16>.allocate(capacity: Self.frameCapacity * 2)
        samples.initialize(repeating: 0, count: Self.frameCapacity * 2)
    }

    deinit {
        samples.deallocate()
    }

    func reset() {
        lock.lock()
        writeIndex = 0
        readIndex = 0
        lock.unlock()
    }

    func write(data: UnsafePointer<Int16>, frames: Int) {
        let mask = Self.frameMask
        let cap = Self.frameCapacity
        let maxQ = Self.maxQueuedFrames

        lock.lock()
        var wIdx = writeIndex
        var rIdx = readIndex

        if (wIdx - rIdx) + frames > maxQ {
            rIdx = max(rIdx, (wIdx + frames) - maxQ)
        }
        if (wIdx - rIdx) + frames > cap {
            rIdx = (wIdx + frames) - cap
        }

        for i in 0..<frames {
            let slot = (wIdx & mask) * 2
            samples[slot]     = data[i * 2]
            samples[slot + 1] = data[i * 2 + 1]
            wIdx += 1
        }

        writeIndex = wIdx
        readIndex = rIdx
        lock.unlock()
    }

    func read(intoLeft leftOut: UnsafeMutablePointer<Float>, rightOut: UnsafeMutablePointer<Float>, count: Int) {
        let mask = Self.frameMask
        let scale: Float = 1.0 / 32768.0

        lock.lock()
        var rIdx = readIndex
        let wIdx = writeIndex
        let available = wIdx - rIdx
        let toRead = min(count, max(0, available))

        for i in 0..<toRead {
            let slot = (rIdx & mask) * 2
            leftOut[i]  = Float(samples[slot]) * scale
            rightOut[i] = Float(samples[slot + 1]) * scale
            rIdx += 1
        }
        readIndex = rIdx
        lock.unlock()

        if toRead < count {
            for i in toRead..<count {
                leftOut[i] = 0
                rightOut[i] = 0
            }
        }
    }
}

/// Low-latency, zero-allocation Audio Engine using AVAudioSourceNode.
/// Eliminates per-frame AVAudioPCMBuffer allocations and scheduleBuffer IPC overhead
/// that would otherwise stall the emulation thread and build up latency over sessions.
final class YDriveAudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var audioFormat: AVAudioFormat?
    private var isStarted = false
    private let ringBuffer = AudioRingBuffer()

    init() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            audioLog.error("Failed to setup AVAudioSession: \(error.localizedDescription)")
        }
    }

    deinit {
        stop()
    }

    /// Configures the engine for the given sample rate and starts it.
    func start(sampleRate: Double) {
        let validRate = sampleRate > 8000 ? sampleRate : 44100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: validRate, channels: 2) else {
            audioLog.error("Failed to create AVAudioFormat")
            return
        }

        ringBuffer.reset()

        if let existingNode = sourceNode {
            engine.detach(existingNode)
            sourceNode = nil
        }

        let rb = self.ringBuffer
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let count = Int(frameCount)
            guard ablPointer.count >= 2,
                  let leftRaw = ablPointer[0].mData,
                  let rightRaw = ablPointer[1].mData else {
                for buf in ablPointer {
                    if let ptr = buf.mData {
                        memset(ptr, 0, Int(buf.mDataByteSize))
                    }
                }
                return noErr
            }

            let leftOut  = leftRaw.assumingMemoryBound(to: Float.self)
            let rightOut = rightRaw.assumingMemoryBound(to: Float.self)
            rb.read(intoLeft: leftOut, rightOut: rightOut, count: count)
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
        ringBuffer.reset()
    }

    /// Enqueues a batch of 16-bit interleaved PCM frames with zero heap allocations.
    func pushAudio(data: UnsafePointer<Int16>, frames: Int) {
        guard isStarted, frames > 0 else { return }
        ringBuffer.write(data: data, frames: frames)
    }
}
