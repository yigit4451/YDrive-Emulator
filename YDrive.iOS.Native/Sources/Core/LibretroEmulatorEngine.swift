// ─────────────────────────────────────────────────────────────────────────────
//  LibretroEmulatorEngine.swift
//  YDrive iOS Native
//
//  Manages the full emulator lifecycle:
//    ROM path → ObjC bridge → retro_init/load/run → frame callback → Metal
//
//  The emulation loop runs on a dedicated background DispatchQueue.
//  All @Published state updates are dispatched to the main actor.
//  The main thread / SwiftUI thread is NEVER blocked.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import os

private let log = Logger(subsystem: "com.yigit.ydrive", category: "EmulatorEngine")

// ── Frame buffer passed to MetalEmulatorView ──────────────────────────────────
struct EmulatorFrame {
    /// Raw pixel data. May be nil on duplicate frames (libretro spec).
    let data: Data?
    let width: Int
    let height: Int
    /// Bytes per row (may be wider than width * bytesPerPixel due to padding)
    let pitch: Int
    let pixelFormat: YDrivePixelFormat
}

// ─────────────────────────────────────────────────────────────────────────────
@MainActor
final class LibretroEmulatorEngine: ObservableObject {

    // ── Public state ─────────────────────────────────────────────────────────
    @Published private(set) var isRunning   = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var coreAvailable = false

    /// Latest rendered frame — observed by MetalEmulatorView
    @Published private(set) var currentFrame: EmulatorFrame?

    /// Geometry reported by the core
    private(set) var videoWidth:  Int   = 320
    private(set) var videoHeight: Int   = 224
    private(set) var aspectRatio: Float = 4.0 / 3.0
    private(set) var targetFPS:   Double = 60.0

    // ── Private ──────────────────────────────────────────────────────────────
    private let bridge     = YDriveLibretroBridge()
    private let audioEngine = YDriveAudioEngine()
    private var emulationQueue: DispatchQueue?
    private var frameTimer: DispatchSourceTimer?

    // ─────────────────────────────────────────────────────────────────────────
    init() {
        log.info("[ENGINE] LibretroEmulatorEngine initialized")
    }

    // ─────────────────────────────────────────────────────────────────────────
    /// Load ROM and start emulation.
    ///
    /// - Parameter romPath: Full filesystem path to the ROM file.
    func start(romPath: String) {
        guard !isRunning else { return }
        errorMessage = nil

        log.info("[ENGINE] start() — ROM: \(romPath, privacy: .public)")

        // Wire up video callback before loadGame
        bridge.onVideoFrame = { @Sendable frame in
            // This is called on the emulation queue — copy data immediately
            // so the raw pointer is safe to hand off across threads.
            let copied: Data?
            if let ptr = frame.data {
                let byteCount = Int(frame.height) * frame.pitch
                copied = byteCount > 0 ? Data(bytes: ptr, count: byteCount) : nil
            } else {
                copied = nil   // duplicate frame — Metal can reuse last texture
            }

            let ef = EmulatorFrame(
                data:        copied,
                width:       Int(frame.width),
                height:      Int(frame.height),
                pitch:       Int(frame.pitch),
                pixelFormat: frame.pixelFormat
            )

            log.debug("[VIDEO] frame \(frame.width)x\(frame.height) pitch=\(frame.pitch) fmt=\(frame.pixelFormat.rawValue)")

            Task { @MainActor [weak self] in
                self?.currentFrame = ef
            }
        }
        
        bridge.onAudioPCM = { [weak audioEngine] data, frames in
            audioEngine?.pushAudio(data: data, frames: frames)
        }

        // Load game on background queue to avoid blocking UI thread
        let queue = DispatchQueue(label: "com.yigit.ydrive.emulation",
                                  qos: .userInteractive)
        self.emulationQueue = queue

        // Capture bridge as nonisolated(unsafe) to satisfy Swift 6 Sendable
        // requirements. YDriveLibretroBridge is ObjC and not Sendable-annotated;
        // we enforce thread safety manually (bridge is only touched on `queue`).
        nonisolated(unsafe) let bridge = self.bridge

        queue.async { @Sendable in
            // Swift imports `- (BOOL)loadGameAtPath:error:` as `throws`.
            // The error: label is swallowed into Swift's throws mechanism.
            var ok = false
            var errorMessage: String = "Emulator core not available"
            do {
                try bridge.loadGame(atPath: romPath)
                ok = true
            } catch {
                errorMessage = error.localizedDescription
            }
            let finalError = errorMessage // Immutable snapshot

            if ok {
                let w = Int(bridge.videoWidth)
                let h = Int(bridge.videoHeight)
                let ar = bridge.aspectRatio
                let fps = bridge.targetFPS
                
                log.info("[ENGINE] Core loaded — \(w)x\(h) @ \(fps, format: .fixed(precision: 2)) fps")
                
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.videoWidth  = w
                    self.videoHeight = h
                    self.aspectRatio = ar
                    self.targetFPS   = fps
                    self.coreAvailable = true
                    self.isRunning   = true
                    
                    self.audioEngine.start(sampleRate: bridge.audioSampleRate)
                    self.startFrameTimer(on: queue, bridge: bridge)
                }
            } else {
                log.error("[ENGINE] Failed to load game: \(finalError, privacy: .public)")
                
                Task { @MainActor [weak self, finalError] in
                    guard let self else { return }
                    self.errorMessage = finalError
                    self.coreAvailable = false
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    /// Stop emulation and release core resources.
    func stop() {
        guard isRunning else { return }
        log.info("[ENGINE] stop()")

        frameTimer?.cancel()
        frameTimer = nil
        isRunning  = false

        audioEngine.stop()

        // Unload on the emulation queue to avoid race with runFrame
        nonisolated(unsafe) let bridgeForUnload = bridge
        emulationQueue?.async { @Sendable in
            bridgeForUnload.unload()
        }
        emulationQueue = nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Input State
    // ─────────────────────────────────────────────────────────────────────────
    
    /// Called from SwiftUI to update input state
    func setButton(_ buttonID: UInt32, pressed: Bool) {
        // bridge.setButton modifies atomic bitmask, safe to call from main thread
        bridge.setButton(buttonID, pressed: pressed)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Private — frame timing loop
    // ─────────────────────────────────────────────────────────────────────────

    private func startFrameTimer(on queue: DispatchQueue, bridge: YDriveLibretroBridge) {
        let fps  = targetFPS > 0 ? targetFPS : 60.0
        let interval = DispatchTimeInterval.nanoseconds(Int(1_000_000_000.0 / fps))

        // Capture bridge as nonisolated(unsafe) — safe because runFrame is
        // always called on this same serial queue.
        nonisolated(unsafe) let capturedBridge = bridge

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .nanoseconds(500_000))
        timer.setEventHandler { @Sendable in
            capturedBridge.runFrame()
        }
        timer.resume()
        self.frameTimer = timer
        log.info("[ENGINE] Frame timer started at \(fps, format: .fixed(precision: 2)) fps")
    }

}
