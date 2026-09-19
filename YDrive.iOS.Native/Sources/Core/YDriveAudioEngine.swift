import Foundation
import AVFoundation
import os

private let audioLog = Logger(subsystem: "com.yigit.ydrive", category: "AudioEngine")

/// A minimal Audio Engine to play 16-bit interleaved stereo PCM from libretro.
/// Designed to be called safely from the background emulation queue.
final class YDriveAudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFormat: AVAudioFormat?

    init() {
        // Prepare AVAudioSession
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            audioLog.error("Failed to setup AVAudioSession: \(error.localizedDescription)")
        }

        engine.attach(playerNode)
    }

    /// Configures the engine for the given sample rate and starts it.
    func start(sampleRate: Double) {
        // Libretro usually outputs 16-bit interleaved stereo PCM
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: sampleRate,
                                         channels: 2,
                                         interleaved: true) else {
            audioLog.error("Failed to create AVAudioFormat")
            return
        }
        
        audioFormat = format
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            playerNode.play()
            audioLog.info("Audio engine started at \(sampleRate) Hz")
        } catch {
            audioLog.error("Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    /// Stops the audio engine and releases resources.
    func stop() {
        playerNode.stop()
        engine.stop()
        audioFormat = nil
        audioLog.info("Audio engine stopped")
    }

    /// Enqueues a batch of 16-bit interleaved PCM frames.
    /// - Parameters:
    ///   - data: Pointer to the raw 16-bit PCM data.
    ///   - frames: Number of frames (1 frame = 2 samples for stereo).
    func pushAudio(data: UnsafePointer<Int16>, frames: Int) {
        guard let format = audioFormat, frames > 0 else { return }

        // Determine capacity required. A frame is 1 sample per channel.
        let frameCount = AVAudioFrameCount(frames)
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }

        // Copy the interleaved 16-bit int data to the buffer's int16ChannelData
        pcmBuffer.frameLength = frameCount
        if let channelData = pcmBuffer.int16ChannelData {
            // Because it's interleaved, both channels are in channelData[0].
            // (AVAudioPCMBuffer with interleaved=true puts everything in the first channel pointer)
            let byteSize = frames * 2 /* channels */ * MemoryLayout<Int16>.size
            memcpy(channelData[0], data, byteSize)
            
            playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
        }
    }
}
