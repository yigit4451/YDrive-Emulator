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

// ─────────────────────────────────────────────────────────────────────────────
@MainActor
final class LibretroEmulatorEngine: ObservableObject {

    // ── Public state ─────────────────────────────────────────────────────────
    @Published private(set) var isRunning   = false
    @Published private(set) var isPaused    = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var coreAvailable = false

    /// Latest rendered frame — observed by MetalEmulatorView
    @Published private(set) var currentFrame: EmulatorFrame?
    
    /// Current frames per second
    @Published private(set) var currentFPS: Double = 0.0
    private var frameCount = 0
    private var lastFPSTime = Date()
    
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

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentFrame = ef
                
                self.frameCount += 1
                let now = Date()
                let elapsed = now.timeIntervalSince(self.lastFPSTime)
                if elapsed >= 1.0 {
                    self.currentFPS = Double(self.frameCount) / elapsed
                    self.frameCount = 0
                    self.lastFPSTime = now
                }
            }
        }
        
        bridge.onAudioPCM = { [weak audioEngine] data, frames in
            audioEngine?.pushAudio(data: data, frames: frames)
        }

        // Load game on background queue to avoid blocking UI thread
        let queue = DispatchQueue(label: "com.yigit.ydrive.emulation",
                                  qos: .userInteractive)
        self.emulationQueue = queue

        // YDriveLibretroBridge is now marked as @Sendable in Objective-C.
        // It uses thread-safe mechanisms internally (atomic properties, locks).
        let bridgeRef = self.bridge

        queue.async { @Sendable in
            // Swift imports `- (BOOL)loadGameAtPath:error:` as `throws`.
            // The error: label is swallowed into Swift's throws mechanism.
            var ok = false
            var errorMessage: String = "Emulator core not available"
            do {
                try bridgeRef.loadGame(atPath: romPath)
                ok = true
            } catch {
                errorMessage = error.localizedDescription
            }
            let finalError = errorMessage // Immutable snapshot

            if ok {
                let w = Int(bridgeRef.videoWidth)
                let h = Int(bridgeRef.videoHeight)
                let ar = bridgeRef.aspectRatio
                let fps = bridgeRef.targetFPS
                
                log.info("[ENGINE] Core loaded — \(w)x\(h) @ \(fps, format: .fixed(precision: 2)) fps")
                
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.videoWidth  = w
                    self.videoHeight = h
                    self.aspectRatio = ar
                    self.targetFPS   = fps
                    self.coreAvailable = true
                    self.isRunning   = true
                    
                    self.lastFPSTime = Date()
                    self.frameCount = 0
                    self.currentFPS = 0.0
                    
                    if self.isAudioEnabled {
                        self.audioEngine.start(sampleRate: bridgeRef.audioSampleRate)
                    }
                    self.startFrameTimer(on: queue, bridge: bridgeRef)
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
        isPaused   = false

        audioEngine.stop()

        // Unload on the emulation queue to avoid race with runFrame
        let bridgeRef = bridge
        emulationQueue?.async { @Sendable in
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
    
    private func getSavesDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let savesDir = docs.appendingPathComponent("Saves", isDirectory: true)
        if !FileManager.default.fileExists(atPath: savesDir.path) {
            try? FileManager.default.createDirectory(at: savesDir, withIntermediateDirectories: true)
        }
        return savesDir
    }
    
    private func saveStateURL(for gameFileName: String, slot: Int) -> URL {
        let safeName = gameFileName.replacingOccurrences(of: "/", with: "_")
        return getSavesDirectory().appendingPathComponent("\(safeName)_slot\(slot).state")
    }
    
    func hasSaveState(for gameFileName: String, slot: Int) -> Bool {
        return FileManager.default.fileExists(atPath: saveStateURL(for: gameFileName, slot: slot).path)
    }
    
    func getSaveStateDate(for gameFileName: String, slot: Int) -> Date? {
        let url = saveStateURL(for: gameFileName, slot: slot)
        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attr?[.modificationDate] as? Date
    }

    func saveState(for gameFileName: String, slot: Int) async -> Bool {
        log.info("[ENGINE] Requesting save state for slot \(slot)")
        let url = saveStateURL(for: gameFileName, slot: slot)
        
        let bridgeRef = bridge
        return await withCheckedContinuation { continuation in
            emulationQueue?.async {
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
        let url = saveStateURL(for: gameFileName, slot: slot)
        
        let bridgeRef = bridge
        return await withCheckedContinuation { continuation in
            emulationQueue?.async {
                guard let data = try? Data(contentsOf: url) else {
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
        let fps  = targetFPS > 0 ? targetFPS : 60.0
        let interval = DispatchTimeInterval.nanoseconds(Int(1_000_000_000.0 / fps))

        let bridgeRef = bridge

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .nanoseconds(500_000))
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
