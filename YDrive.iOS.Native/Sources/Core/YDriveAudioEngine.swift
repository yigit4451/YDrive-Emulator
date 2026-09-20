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
        // AVAudioEngine prefers standard float32 non-interleaved format
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
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

        pcmBuffer.frameLength = frameCount
        
        // Convert interleaved 16-bit to non-interleaved float32
        if let floatData = pcmBuffer.floatChannelData {
            let leftChannel = floatData[0]
            let rightChannel = floatData[1]
            
            for i in 0..<frames {
                // PCM values are from -32768 to 32767
                leftChannel[i] = Float(data[i * 2]) / 32768.0
                rightChannel[i] = Float(data[i * 2 + 1]) / 32768.0
            }
            
            playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
        }
    }
}
