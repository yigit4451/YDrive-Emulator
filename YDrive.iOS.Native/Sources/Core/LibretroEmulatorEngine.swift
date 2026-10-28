// ─────────────────────────────────────────────────────────────────────────────
//  LibretroEmulatorEngine.swift
//  YDrive iOS Native
//
//  Manages the full emulator lifecycle:
//    ROM path → ObjC bridge → retro_init/load/run → frame callback → Metal
//
//  The emulation loop runs on a dedicated serial background DispatchQueue.
//  All @Published state updates are dispatched to the main actor.
//  The main thread / SwiftUI thread is NEVER blocked.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import UIKit
import os

private let log = Logger(subsystem: "com.yigit.ydrive", category: "EmulatorEngine")

// ── Frame buffer passed to MetalEmulatorView ──────────────────────────────────
struct EmulatorFrame: Sendable {
    /// Raw pixel data. May be nil on duplicate frames (libretro spec).
    let data: Data?
    let width: Int
    let height: Int
    /// Bytes per row (may be wider than width * bytesPerPixel due to padding)
    let pitch: Int
    let pixelFormat: YDrivePixelFormat
}

/// Consumer protocol for direct, zero-delay video frame delivery from the emulation queue to Metal
protocol VideoFrameConsumer: AnyObject, Sendable {
    func enqueueFrame(_ frame: EmulatorFrame)
}

// ─────────────────────────────────────────────────────────────────────────────
@MainActor
final class LibretroEmulatorEngine: ObservableObject {

    /// Single shared serial queue for all libretro C core operations across the entire app lifecycle.
    /// Because the statically linked libretro core has global C state, serializing all load, runFrame,
    /// and unload calls on one queue guarantees two sessions can never race or overlap.
    private static let sharedEmulationQueue = DispatchQueue(
        label: "com.yigit.ydrive.emulation.serial",
        qos: .userInteractive
    )

    // ── Video delivery hub (thread-safe, eliminates main-thread hopping) ───────
    private final class VideoFrameHub: @unchecked Sendable {
        private let lock = NSLock()
        private var _consumer: (any VideoFrameConsumer)?
        private var _latestFrame: EmulatorFrame?
        private var _frameCount: Int = 0
        private var _lastFPSTime: Date = Date()
        private var _fps: Double = 0.0

        var consumer: (any VideoFrameConsumer)? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _consumer
            }
            set {
                lock.lock()
                _consumer = newValue
                lock.unlock()
            }
        }

        var latestFrame: EmulatorFrame? {
            lock.lock()
            defer { lock.unlock() }
            return _latestFrame
        }

        var fps: Double {
            lock.lock()
            defer { lock.unlock() }
            return _fps
        }

        func handleFrame(_ ef: EmulatorFrame) {
            lock.lock()
            _latestFrame = ef
            let cons = _consumer
            _frameCount += 1
            let now = Date()
            let elapsed = now.timeIntervalSince(_lastFPSTime)
            if elapsed >= 1.0 {
                _fps = Double(_frameCount) / elapsed
                _frameCount = 0
                _lastFPSTime = now
            }
            lock.unlock()

            cons?.enqueueFrame(ef)
        }

        func resetFPS() {
            lock.lock()
            _frameCount = 0
            _lastFPSTime = Date()
            _fps = 0.0
            lock.unlock()
        }
    }

    private let videoHub = VideoFrameHub()

    /// Direct consumer for video frames (MetalCoordinator)
    var videoFrameConsumer: (any VideoFrameConsumer)? {
        get { videoHub.consumer }
        set { videoHub.consumer = newValue }
    }

    // ── Public state ─────────────────────────────────────────────────────────
    @Published private(set) var isRunning   = false
    @Published private(set) var isPaused    = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var coreAvailable = false

    /// Latest rendered frame — queried for screenshots (thread-safe, not published to prevent 60fps view invalidations)
    var currentFrame: EmulatorFrame? {
        videoHub.latestFrame
    }
    
    /// Current frames per second
    var currentFPS: Double {
        videoHub.fps
    }
    
    var isAudioEnabled = true {
        didSet {
            if isAudioEnabled {
                if isRunning && !isPaused {
                    audioEngine.start(sampleRate: bridge.audioSampleRate)
                }
            } else {
                audioEngine.stop()
            }
        }
    }

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
    /// True between start() and the moment the core finished loading (or failed).
    private var isStarting = false
    /// Incremented on every start()/stop() so late async completions can detect they are stale.
    private var sessionID = 0

    // ─────────────────────────────────────────────────────────────────────────
    init() {
        log.info("[ENGINE] LibretroEmulatorEngine initialized")
    }

    // ─────────────────────────────────────────────────────────────────────────
    /// Load ROM and start emulation.
    ///
    /// - Parameter romPath: Full filesystem path to the ROM file.
    func start(romPath: String) {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        sessionID += 1
        let session = sessionID
        errorMessage = nil

        log.info("[ENGINE] start() — ROM: \(romPath, privacy: .public)")

        // Wire up video callback before loadGame
        let hub = self.videoHub
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

            hub.handleFrame(ef)
        }
        
        bridge.onAudioPCM = { [weak audioEngine] data, frames in
            audioEngine?.pushAudio(data: data, frames: frames)
        }

        // TEMP diagnostics: press -> libretro poll latency.
        bridge.onInputPolled = { @Sendable buttonID, latencyMs in
            InputLatencyProbe.log(String(format: "poll   id=%u press→poll=%.2fms", buttonID, latencyMs))
        }
        bridge.onInputTrace = { @Sendable message in
            InputLatencyProbe.log(message)
        }
        InputLatencyProbe.log("---- session start (build 9) ----")

        // Use the single shared serial emulation queue so previous session unload()
        // always finishes before the next session's loadGame() begins.
        let queue = Self.sharedEmulationQueue
        self.emulationQueue = queue

        let bridgeRef = self.bridge

        queue.async { @Sendable in
            var ok = false
            var errorMessage: String = "Emulator core not available"
            do {
                try bridgeRef.loadGame(atPath: romPath)
                ok = true
            } catch {
                errorMessage = error.localizedDescription
            }
            let finalError = errorMessage

            if ok {
                let w = Int(bridgeRef.videoWidth)
                let h = Int(bridgeRef.videoHeight)
                let ar = bridgeRef.aspectRatio
                let fps = bridgeRef.targetFPS
                
                log.info("[ENGINE] Core loaded — \(w)x\(h) @ \(fps, format: .fixed(precision: 2)) fps")
                
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // stop() was called while the core was still loading: tear it down again.
                    guard self.sessionID == session else {
                        queue.async { @Sendable in bridgeRef.unload() }
                        return
                    }
                    self.isStarting = false
                    self.videoWidth  = w
                    self.videoHeight = h
                    self.aspectRatio = ar
                    self.targetFPS   = fps
                    self.coreAvailable = true
                    self.isRunning   = true
                    
                    self.videoHub.resetFPS()
                    
                    if self.isAudioEnabled {
                        self.audioEngine.start(sampleRate: bridgeRef.audioSampleRate)
                    }
                    self.startFrameTimer(on: queue, bridge: bridgeRef)
                }
            } else {
                log.error("[ENGINE] Failed to load game: \(finalError, privacy: .public)")
                
                Task { @MainActor [weak self, finalError] in
                    guard let self, self.sessionID == session else { return }
                    self.isStarting = false
                    self.errorMessage = finalError
                    self.coreAvailable = false
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    /// Stop emulation and release core resources.
    func stop() {
        guard isRunning || isStarting else { return }
        log.info("[ENGINE] stop()")

        // Invalidate any load that is still in flight.
        sessionID += 1
        isStarting = false

        frameTimer?.cancel()
        frameTimer = nil
        isRunning  = false
        isPaused   = false

        audioEngine.stop()

        // Unload on the shared serial emulation queue
        let bridgeRef = bridge
        Self.sharedEmulationQueue.async { @Sendable in
            bridgeRef.unload()
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
    // MARK: - Game Lifecycle Actions
    // ─────────────────────────────────────────────────────────────────────────
    
    func setPaused(_ paused: Bool) {
        self.isPaused = paused
        // bridge.isPaused is an atomic property, safe to write from MainActor
        bridge.isPaused = paused
        
        if paused || !isAudioEnabled {
            audioEngine.stop()
        } else {
            audioEngine.start(sampleRate: bridge.audioSampleRate)
        }
    }
    
    func reset() {
        let bridgeRef = bridge
        emulationQueue?.async {
            bridgeRef.reset()
        }
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Save / Load States
    // ─────────────────────────────────────────────────────────────────────────
    
    private func getSavesDirectory(for gameFileName: String) -> URL {
        let gameURL = URL(fileURLWithPath: gameFileName)
        let gameDir = gameURL.deletingLastPathComponent()
        if gameDir.path.contains("ROM's") && gameDir.lastPathComponent != "ROM's" {
            return gameDir
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let savesDir = docs.appendingPathComponent("Saves", isDirectory: true)
        if !FileManager.default.fileExists(atPath: savesDir.path) {
            try? FileManager.default.createDirectory(at: savesDir, withIntermediateDirectories: true)
        }
        return savesDir
    }
    
    private func saveStateURL(for gameFileName: String, slot: Int) -> URL {
        let gameURL = URL(fileURLWithPath: gameFileName)
        let gameDir = gameURL.deletingLastPathComponent()
        if gameDir.path.contains("ROM's") && gameDir.lastPathComponent != "ROM's" {
            return gameDir.appendingPathComponent("slot\(slot).state")
        }
        let safeName = gameFileName.replacingOccurrences(of: "/", with: "_")
        return getSavesDirectory(for: gameFileName).appendingPathComponent("\(safeName)_slot\(slot).state")
    }
    
    func hasSaveState(for gameFileName: String, slot: Int) -> Bool {
        let url = saveStateURL(for: gameFileName, slot: slot)
        if FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let legacyURL = docs.appendingPathComponent("Saves").appendingPathComponent("\(gameFileName.replacingOccurrences(of: "/", with: "_"))_slot\(slot).state")
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                return true
            }
        }
        return false
    }
    
    func getSaveStateDate(for gameFileName: String, slot: Int) -> Date? {
        let url = saveStateURL(for: gameFileName, slot: slot)
        if let attr = try? FileManager.default.attributesOfItem(atPath: url.path) {
            return attr[.modificationDate] as? Date
        }
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let legacyURL = docs.appendingPathComponent("Saves").appendingPathComponent("\(gameFileName.replacingOccurrences(of: "/", with: "_"))_slot\(slot).state")
            let attr = try? FileManager.default.attributesOfItem(atPath: legacyURL.path)
            return attr?[.modificationDate] as? Date
        }
        return nil
    }

    func saveState(for gameFileName: String, slot: Int) async -> Bool {
        log.info("[ENGINE] Requesting save state for slot \(slot)")
        let url = saveStateURL(for: gameFileName, slot: slot)
        
        let bridgeRef = bridge
        return await withCheckedContinuation { continuation in
            Self.sharedEmulationQueue.async {
                guard let data = bridgeRef.saveState() else {
                    continuation.resume(returning: false)
                    return
                }
                do {
                    try data.write(to: url, options: .atomic)
                    continuation.resume(returning: true)
                } catch {
                    log.error("[ENGINE] Failed to write save state: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    func loadState(for gameFileName: String, slot: Int) async -> Bool {
        log.info("[ENGINE] Requesting load state for slot \(slot)")
        var url = saveStateURL(for: gameFileName, slot: slot)
        if !FileManager.default.fileExists(atPath: url.path) {
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let legacyURL = docs.appendingPathComponent("Saves").appendingPathComponent("\(gameFileName.replacingOccurrences(of: "/", with: "_"))_slot\(slot).state")
                if FileManager.default.fileExists(atPath: legacyURL.path) {
                    url = legacyURL
                }
            }
        }
        
        let bridgeRef = bridge
        let targetURL = url
        return await withCheckedContinuation { continuation in
            Self.sharedEmulationQueue.async {
                guard let data = try? Data(contentsOf: targetURL) else {
                    continuation.resume(returning: false)
                    return
                }
                let success = bridgeRef.loadState(data)
                continuation.resume(returning: success)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Private — frame timing loop
    // ─────────────────────────────────────────────────────────────────────────

    private func startFrameTimer(on queue: DispatchQueue, bridge: YDriveLibretroBridge) {
        frameTimer?.cancel()
        frameTimer = nil

        let fps  = targetFPS > 0 ? targetFPS : 60.0
        let interval = DispatchTimeInterval.nanoseconds(Int(1_000_000_000.0 / fps))

        let bridgeRef = bridge

        // Use normal DispatchSource timer (without .strict) with 1ms leeway to avoid
        // kernel thread-starvation bursts and catch-up stutters that freeze the UI thread.
        let timer = DispatchSource.makeTimerSource(flags: [], queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { @Sendable in
            guard !bridgeRef.isPaused else { return }
            bridgeRef.runFrame()
        }
        timer.resume()
        self.frameTimer = timer
        log.info("[ENGINE] Frame timer started at \(fps, format: .fixed(precision: 2)) fps")
    }

}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Screenshot Generator
// ─────────────────────────────────────────────────────────────────────────────
enum ScreenshotGenerator {
    static func generateScreenshotImage(from frame: EmulatorFrame) -> UIImage? {
        guard let data = frame.data else { return nil }
        
        let w = frame.width
        let h = frame.height
        let pitch = frame.pitch
        let format = frame.pixelFormat
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        
        let dest = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
        defer { dest.deallocate() }
        
        switch format {
        case .xrgb8888:
            data.withUnsafeBytes { ptr in
                dest.update(from: ptr.bindMemory(to: UInt32.self).baseAddress!, count: w * h)
            }
        case .rgb565:
            data.withUnsafeBytes { src in
                let src16 = src.bindMemory(to: UInt16.self)
                for y in 0..<h {
                    let rowSrc = src16.baseAddress!.advanced(by: y * (pitch / 2))
                    let rowDst = dest.advanced(by: y * w)
                    for x in 0..<w {
                        let p  = rowSrc[x]
                        let r5 = UInt32((p >> 11) & 0x1F)
                        let g6 = UInt32((p >> 5)  & 0x3F)
                        let b5 = UInt32( p         & 0x1F)
                        let r8 = (r5 << 3) | (r5 >> 2)
                        let g8 = (g6 << 2) | (g6 >> 4)
                        let b8 = (b5 << 3) | (b5 >> 2)
                        rowDst[x] = 0xFF000000 | (r8 << 16) | (g8 << 8) | b8
                    }
                }
            }
        case .trgb1555:
            data.withUnsafeBytes { src in
                let src16 = src.bindMemory(to: UInt16.self)
                for y in 0..<h {
                    let rowSrc = src16.baseAddress!.advanced(by: y * (pitch / 2))
                    let rowDst = dest.advanced(by: y * w)
                    for x in 0..<w {
                        let p  = rowSrc[x]
                        let r5 = UInt32((p >> 10) & 0x1F)
                        let g5 = UInt32((p >> 5)  & 0x1F)
                        let b5 = UInt32( p         & 0x1F)
                        let r8 = (r5 << 3) | (r5 >> 2)
                        let g8 = (g5 << 3) | (g5 >> 2)
                        let b8 = (b5 << 3) | (b5 >> 2)
                        rowDst[x] = 0xFF000000 | (r8 << 16) | (g8 << 8) | b8
                    }
                }
            }
        @unknown default:
            return nil
        }
        
        guard let context = CGContext(data: dest,
                                      width: w,
                                      height: h,
                                      bitsPerComponent: 8,
                                      bytesPerRow: w * 4,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo),
              let cgImage = context.makeImage() else { return nil }
              
        return UIImage(cgImage: cgImage)
    }
}
