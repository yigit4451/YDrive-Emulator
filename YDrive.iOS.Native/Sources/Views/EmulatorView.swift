import SwiftUI
import GameController
import os

private let emulatorLog = Logger(subsystem: "com.yigit.ydrive", category: "EmulatorView")

struct EmulatorView: View {
    let game: GameItem
    @Environment(\.dismiss) private var dismiss
    @State private var isControllerConnected = false
    @StateObject private var engine = LibretroEmulatorEngine()
    @State private var isTopBarVisible = false
    @State private var isPaused = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ── Game render surface ───────────────────────────────────────────
            if engine.coreAvailable {
                // Real libretro core is running — show Metal output
                MetalEmulatorView(engine: engine)
                    .ignoresSafeArea()
            } else if let errorMsg = engine.errorMessage {
                // Core not available or load failed — show diagnostic info
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.yellow)
                    Text("Emulator Core Unavailable")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                // Loading state
                ProgressView()
                    .tint(.white)
            }

            // ── On-screen controls ───────────────────────────────────────────
            if !isControllerConnected {
                VStack {
                    Spacer()
                    OnScreenControlsView(engine: engine)
                        .padding(.bottom, 32)
                }
            }

            // ── Floating Menu Button ─────────────────────────────────────────
            if !isTopBarVisible {
                VStack {
                    HStack {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isTopBarVisible = true
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        }
                        .padding(16)
                        Spacer()
                    }
                    Spacer()
                }
            }

            // ── Top Bar Overlay ──────────────────────────────────────────────
            if isTopBarVisible {
                VStack {
                    topBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(10)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            observeControllers()
            startEmulator()
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self)
            engine.stop()
        }
    }

    // ── Top Bar Implementation ────────────────────────────────────────────────
    private var topBar: some View {
        HStack(spacing: 16) {
            // Game title
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(.blue)
                Text(game.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())

            Spacer()

            // Pause
            Button {
                // Toggle pause logic (to be implemented in bridge later, or stop timer)
                // For now, it's just a visual toggle
                isPaused.toggle()
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)

            // Reset (stub)
            Button {
                // Stub reset
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)

            // Exit
            Button {
                engine.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.red.opacity(0.8))
            }
            .padding(.horizontal, 8)

            // Close Bar
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isTopBarVisible = false
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.title3.bold())
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.white.opacity(0.1)),
            alignment: .bottom
        )
    }
        }
        .statusBarHidden(true)
        .onAppear {
            observeControllers()
            startEmulator()
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self)
            engine.stop()
        }
    }

    // ── ROM path resolution ───────────────────────────────────────────────────
    private func startEmulator() {
        // Resolve ROM to a full filesystem path.
        // GameLibraryViewModel.addRom stores only the fileName; the actual
        // copied file lives in the app's Documents directory.
        let romPath = resolveRomPath(for: game.fileName)
        emulatorLog.info("[VIEW] Starting emulator for: \(game.title, privacy: .public)")
        emulatorLog.info("[VIEW] ROM path: \(romPath, privacy: .public)")
        engine.start(romPath: romPath)
    }

    private func resolveRomPath(for fileName: String) -> String {
        // If fileName is already an absolute path, use it directly.
        if fileName.hasPrefix("/") { return fileName }

        // Otherwise look in Documents (where the file importer copies ROMs).
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(fileName).path ?? fileName
    }

    // ── Controller observation ────────────────────────────────────────────────
    private func observeControllers() {
        let check: @Sendable () -> Void = {
            Task { @MainActor in
                self.isControllerConnected = !GCController.controllers().isEmpty
            }
        }
        check()
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main) { _ in check() }
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main) { _ in check() }
    }
}

// MARK: – On-Screen Controls

struct OnScreenControlsView: View {
    @ObservedObject var engine: LibretroEmulatorEngine

    // RetroPad IDs
    let ID_B: UInt32 = 0
    let ID_Y: UInt32 = 1
    let ID_SELECT: UInt32 = 2
    let ID_START: UInt32 = 3
    let ID_UP: UInt32 = 4
    let ID_DOWN: UInt32 = 5
    let ID_LEFT: UInt32 = 6
    let ID_RIGHT: UInt32 = 7
    let ID_A: UInt32 = 8

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            if isLandscape {
                // LANDSCAPE: Controls pushed to far corners
                HStack(alignment: .bottom) {
                    dpadArea
                        .padding(.leading, safePadding(geo))
                    Spacer()
                    actionArea
                        .padding(.trailing, safePadding(geo))
                }
                .padding(.bottom, safePadding(geo))
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                // PORTRAIT: D-pad left-mid, Actions right-mid, Start center
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        dpadArea
                            .padding(.leading, 16)
                        
                        Spacer()
                        
                        VStack(spacing: 24) {
                            actionButton("START", color: .white, size: 45) { engine.setButton(ID_START, pressed: $0) }
                                .padding(.bottom, 20)
                            
                            actionArea
                        }
                        .padding(.trailing, 16)
                    }
                    .padding(.bottom, 48)
                }
            }
        }
    }
    
    private func safePadding(_ geo: GeometryProxy) -> CGFloat {
        return geo.safeAreaInsets.bottom > 0 ? 32 : 16
    }
    
    private var dpadArea: some View {
        // MultiTouchDPad gives us zero-latency up/down/left/right
        MultiTouchDPad { up, down, left, right in
            engine.setButton(ID_UP, pressed: up)
            engine.setButton(ID_DOWN, pressed: down)
            engine.setButton(ID_LEFT, pressed: left)
            engine.setButton(ID_RIGHT, pressed: right)
        }
        .frame(width: 160, height: 160)
        .background(
            ZStack {
                Path { path in
                    let size: CGFloat = 160
                    let w: CGFloat = 52
                    let h = size
                    path.addRoundedRect(in: CGRect(x: (size - w)/2, y: 0, width: w, height: h), cornerSize: CGSize(width: 8, height: 8))
                    path.addRoundedRect(in: CGRect(x: 0, y: (size - w)/2, width: h, height: w), cornerSize: CGSize(width: 8, height: 8))
                }
                .fill(Color(white: 0.1).opacity(0.6))
                .overlay(
                    Path { path in
                        let size: CGFloat = 160
                        let w: CGFloat = 52
                        let h = size
                        path.addRoundedRect(in: CGRect(x: (size - w)/2, y: 0, width: w, height: h), cornerSize: CGSize(width: 8, height: 8))
                        path.addRoundedRect(in: CGRect(x: 0, y: (size - w)/2, width: h, height: w), cornerSize: CGSize(width: 8, height: 8))
                    }.stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 32, height: 32)
            }
        )
    }
    
    private var actionArea: some View {
        HStack(spacing: 8) {
            // SEGA A maps to Retro Y (1)
            actionButton("A", color: .red) { engine.setButton(ID_Y, pressed: $0) }
                .offset(y: 24)
            // SEGA B maps to Retro B (0)
            actionButton("B", color: .blue) { engine.setButton(ID_B, pressed: $0) }
            // SEGA C maps to Retro A (8)
            actionButton("C", color: .yellow) { engine.setButton(ID_A, pressed: $0) }
                .offset(y: -24)
        }
    }

    private func actionButton(
        _ label: String,
        color: Color,
        size: CGFloat = 64,
        onPress: @escaping (Bool) -> Void
    ) -> some View {
        MultiTouchButton { isPressed in
            onPress(isPressed)
        }
        .frame(width: size + 20, height: size + 20) // Give the touch target extra padding
        .background(
            ZStack {
                Circle()
                    .fill(Color(white: 0.1).opacity(0.6))
                    .frame(width: size, height: size)
                    .overlay(
                        Circle().stroke(color.opacity(0.5), lineWidth: 2)
                    )
                
                Text(label)
                    .font(.system(size: label.count > 1 ? 14 : 22, weight: .bold, design: .rounded))
                    .foregroundStyle(color.opacity(0.9))
            }
        )
    }
}

#Preview {
    EmulatorView(game: GameItem(
        title: "Sonic the Hedgehog",
        consoleName: "SEGA Genesis",
        fileName: "sonic.bin"
    ))
}
