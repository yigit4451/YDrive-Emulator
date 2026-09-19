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
            let w = geo.size.width
            let h = geo.size.height
            let isLandscape = w > h
            
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom
            let safeLeft = geo.safeAreaInsets.leading
            let safeRight = geo.safeAreaInsets.trailing

            // Scale down controls in portrait to fit narrow screens
            let scale: CGFloat = isLandscape ? 1.0 : 0.8
            
            let dpadSize: CGFloat = 200 * scale
            let dpadR = dpadSize / 2
            
            let abcWidth: CGFloat = 260 * scale
            let abcHeight: CGFloat = 130 * scale
            let abcW = abcWidth / 2
            let abcH = abcHeight / 2
            
            let startSize: CGFloat = 80 * scale
            let startR = startSize / 2

            let padX: CGFloat = isLandscape ? (safeLeft > 0 ? safeLeft + 4 : 24) : 16
            let padY: CGFloat = isLandscape ? (safeBottom > 0 ? safeBottom + 4 : 24) : 16

            // Compute Centers ensuring we stay within safe bounds
            let centers: (dpad: CGPoint, abc: CGPoint, start: CGPoint) = {
                if isLandscape {
                    return (
                        dpad: CGPoint(
                            x: padX + dpadR,
                            y: h - padY - dpadR
                        ),
                        abc: CGPoint(
                            x: w - safeRight - (isLandscape ? 16 : 0) - abcW,
                            y: h - padY - abcH
                        ),
                        start: CGPoint(
                            x: w / 2,
                            y: h - padY - startR
                        )
                    )
                } else {
                    // Portrait: DPad Left, ABC Right, Start Center-Bottom
                    let availableBottomY = h - safeBottom - 16
                    let startC = CGPoint(
                        x: w / 2,
                        y: availableBottomY - startR
                    )
                    
                    let controlsY = availableBottomY - startSize - 16 - dpadR
                    return (
                        dpad: CGPoint(
                            x: safeLeft + 16 + dpadR,
                            y: controlsY
                        ),
                        abc: CGPoint(
                            x: w - safeRight - 16 - abcW,
                            y: controlsY
                        ),
                        start: startC
                    )
                }
            }()

            ZStack(alignment: .topLeading) {
                // D-Pad
                dpadArea(size: dpadSize, scale: scale)
                    .position(centers.dpad)
                
                // A B C Buttons
                actionArea(width: abcWidth, height: abcHeight, scale: scale)
                    .position(centers.abc)
                
                // START Button
                startButton(scale: scale)
                    .position(centers.start)
            }
        }
    }
    
    private func dpadArea(size: CGFloat, scale: CGFloat) -> some View {
        MultiTouchDPad { up, down, left, right in
            engine.setButton(ID_UP, pressed: up)
            engine.setButton(ID_DOWN, pressed: down)
            engine.setButton(ID_LEFT, pressed: left)
            engine.setButton(ID_RIGHT, pressed: right)
        }
        .frame(width: size, height: size)
        .background(
            ZStack {
                let visualSize: CGFloat = 160 * scale
                
                // Base Circle (Frosted Glass D-Pad Base)
                Circle()
                    .fill(Color(red: 18/255, green: 19/255, blue: 26/255).opacity(0.44)) // #7012131A
                    .frame(width: visualSize, height: visualSize)
                    .overlay(
                        Circle().stroke(Color(red: 168/255, green: 199/255, blue: 250/255).opacity(0.31), lineWidth: 2 * scale) // #50A8C7FA
                    )
                
                // Center Thumb Hub
                Circle()
                    .fill(Color.white.opacity(0.19)) // #30FFFFFF
                    .frame(width: 50 * scale, height: 50 * scale)
                
                // Directional Arrows
                let offset = visualSize * 0.32
                let iconSize = 22 * scale
                let iconColor = Color(red: 240/255, green: 244/255, blue: 249/255)
                
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(iconColor)
                    .offset(y: -offset)
                
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(iconColor)
                    .offset(y: offset)
                
                Image(systemName: "arrowtriangle.left.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(iconColor)
                    .offset(x: -offset)
                
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(iconColor)
                    .offset(x: offset)
            }
        )
    }
    
    private func actionArea(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        ZStack {
            let btnSize: CGFloat = 68 * scale
            let hitSize: CGFloat = 88 * scale
            let bgColor = Color(red: 0, green: 71/255, blue: 171/255) // #0047AB
            let borderColor = Color(red: 100/255, green: 181/255, blue: 246/255) // #64B5F6
            
            // SEGA A maps to Retro Y (1)
            actionButton("A", color: bgColor, borderColor: borderColor, visualSize: btnSize, hitSize: hitSize) { engine.setButton(ID_Y, pressed: $0) }
                .position(x: hitSize/2, y: height - hitSize/2)
            
            // SEGA B maps to Retro B (0)
            actionButton("B", color: bgColor, borderColor: borderColor, visualSize: btnSize, hitSize: hitSize) { engine.setButton(ID_B, pressed: $0) }
                .position(x: width/2, y: height/2)
            
            // SEGA C maps to Retro A (8)
            actionButton("C", color: bgColor, borderColor: borderColor, visualSize: btnSize, hitSize: hitSize) { engine.setButton(ID_A, pressed: $0) }
                .position(x: width - hitSize/2, y: hitSize/2)
        }
        .frame(width: width, height: height)
    }

    private func actionButton(
        _ label: String,
        color: Color,
        borderColor: Color,
        visualSize: CGFloat,
        hitSize: CGFloat,
        onPress: @escaping (Bool) -> Void
    ) -> some View {
        MultiTouchButton { isPressed in
            onPress(isPressed)
        }
        .frame(width: hitSize, height: hitSize)
        .background(
            ZStack {
                Circle()
                    .fill(color.opacity(0.4))
                    .frame(width: visualSize, height: visualSize)
                    .overlay(
                        Circle().stroke(borderColor.opacity(0.8), lineWidth: 2 * (visualSize/68))
                    )
                
                Text(label)
                    .font(.system(size: 20 * (visualSize/68), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        )
    }
    
    private func startButton(scale: CGFloat) -> some View {
        let width = 80 * scale
        let height = 40 * scale
        let hitSize = 80 * scale
        
        return MultiTouchButton { isPressed in
            engine.setButton(ID_START, pressed: isPressed)
        }
        .frame(width: width + 40, height: height + 40)
        .background(
            ZStack {
                Capsule()
                    .fill(Color(white: 0.13).opacity(0.4)) // #66212121
                    .frame(width: width, height: height)
                    .overlay(
                        Capsule().stroke(Color(white: 0.88).opacity(0.6), lineWidth: 1.5 * scale) // #99E0E0E0
                    )
                
                Text("START")
                    .font(.system(size: 12 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(white: 0.93)) // #EEEEEE
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
