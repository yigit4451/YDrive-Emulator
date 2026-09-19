import SwiftUI
import GameController
import os

private let emulatorLog = Logger(subsystem: "com.yigit.ydrive", category: "EmulatorView")

struct EmulatorView: View {
    let game: GameItem
    @Environment(\.dismiss) private var dismiss
    @State private var isControllerConnected = false
    @State private var buttonStates = ButtonState()
    @StateObject private var engine = LibretroEmulatorEngine()

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
                    OnScreenControlsView(buttonStates: $buttonStates)
                        .padding(.bottom, 48)
                }
            }

            // ── Top Bar ──────────────────────────────────────────────────────
            VStack {
                HStack {
                    Button {
                        engine.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.7), .black.opacity(0.4))
                    }
                    .padding(16)

                    Spacer()

                    Text(game.title)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .applyLiquidGlassCapsule()
                        .padding(.trailing, 64)

                    Spacer()
                }
                Spacer()
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

struct ButtonState {
    var up = false, down = false, left = false, right = false
    var a = false, b = false, c = false, start = false
}

struct OnScreenControlsView: View {
    @Binding var buttonStates: ButtonState

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
                            .padding(.leading, 24)
                        
                        Spacer()
                        
                        VStack(spacing: 24) {
                            actionButton("START", color: .white, size: 50) { buttonStates.start = $0 }
                                .padding(.bottom, 20)
                            
                            actionArea
                        }
                        .padding(.trailing, 24)
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
        DPadView(
            onUp: { buttonStates.up = $0 },
            onDown: { buttonStates.down = $0 },
            onLeft: { buttonStates.left = $0 },
            onRight: { buttonStates.right = $0 }
        )
    }
    
    private var actionArea: some View {
        HStack(spacing: 12) {
            actionButton("A", color: .red)    { buttonStates.a = $0 }
                .offset(y: 24)
            actionButton("B", color: .blue)   { buttonStates.b = $0 }
            actionButton("C", color: .yellow) { buttonStates.c = $0 }
                .offset(y: -24)
        }
    }

    private func actionButton(
        _ label: String,
        color: Color,
        size: CGFloat = 64,
        onPress: @escaping (Bool) -> Void
    ) -> some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.1).opacity(0.8))
                .frame(width: size, height: size)
                .overlay(
                    Circle().stroke(color.opacity(0.6), lineWidth: 2)
                )
            
            Text(label)
                .font(.system(size: label.count > 1 ? 14 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(color.opacity(0.9))
        }
        .padding(16) // Increase invisible hit area
        .contentShape(Circle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress(true) }
                .onEnded   { _ in onPress(false) }
        )
    }
}

// MARK: – D-Pad
struct DPadView: View {
    var onUp: (Bool) -> Void
    var onDown: (Bool) -> Void
    var onLeft: (Bool) -> Void
    var onRight: (Bool) -> Void
    
    @State private var location: CGPoint? = nil

    var body: some View {
        let size: CGFloat = 160
        let center = size / 2
        let threshold: CGFloat = 20

        ZStack {
            // Background cross
            Path { path in
                let w: CGFloat = 52
                let h = size
                // vertical
                path.addRoundedRect(in: CGRect(x: (size - w)/2, y: 0, width: w, height: h), cornerSize: CGSize(width: 8, height: 8))
                // horizontal
                path.addRoundedRect(in: CGRect(x: 0, y: (size - w)/2, width: h, height: w), cornerSize: CGSize(width: 8, height: 8))
            }
            .fill(Color(white: 0.1).opacity(0.8))
            .overlay(
                Path { path in
                    let w: CGFloat = 52
                    let h = size
                    path.addRoundedRect(in: CGRect(x: (size - w)/2, y: 0, width: w, height: h), cornerSize: CGSize(width: 8, height: 8))
                    path.addRoundedRect(in: CGRect(x: 0, y: (size - w)/2, width: h, height: w), cornerSize: CGSize(width: 8, height: 8))
                }.stroke(Color.white.opacity(0.2), lineWidth: 1)
            )

            // Inner pivot
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: 32, height: 32)
                
            // Arrows
            Image(systemName: "chevron.up").offset(y: -size/3).foregroundStyle(.white.opacity(0.6))
            Image(systemName: "chevron.down").offset(y: size/3).foregroundStyle(.white.opacity(0.6))
            Image(systemName: "chevron.left").offset(x: -size/3).foregroundStyle(.white.opacity(0.6))
            Image(systemName: "chevron.right").offset(x: size/3).foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle()) // Capture touches anywhere in the square
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    location = value.location
                    let dx = value.location.x - center
                    let dy = value.location.y - center
                    
                    onLeft(dx < -threshold)
                    onRight(dx > threshold)
                    onUp(dy < -threshold)
                    onDown(dy > threshold)
                }
                .onEnded { _ in
                    location = nil
                    onLeft(false)
                    onRight(false)
                    onUp(false)
                    onDown(false)
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
