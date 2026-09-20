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
    @State private var isSaveManagerPresented = false

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
                OnScreenControlsView(engine: engine)
                    .ignoresSafeArea()
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
        .sheet(isPresented: $isSaveManagerPresented) {
            SaveManagerView(engine: engine, gameFileName: game.fileName, isPresented: $isSaveManagerPresented)
        }
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
        HStack(spacing: 12) {
            // Game title
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(.blue)
                Text(game.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .applyLiquidGlassCapsule()

            Spacer()

            // Pause
            Button {
                engine.setPaused(!engine.isPaused)
            } label: {
                Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .applyLiquidGlassCircle()
            }
            
            // Saves
            Button {
                withAnimation {
                    engine.setPaused(true)
                    isSaveManagerPresented = true
                    isTopBarVisible = false
                }
            } label: {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .applyLiquidGlassCircle()
            }

            // Reset
            Button {
                engine.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .applyLiquidGlassCircle()
            }

            // Exit
            Button {
                engine.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.bold())
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
                    .applyLiquidGlassCircle()
            }

            // Close Bar
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isTopBarVisible = false
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.title3.bold())
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .applyLiquidGlassCircle()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
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
            
            let minDim = min(w, h)
            
            // Dynamic proportional sizes based on screen size
            let btnVisual = minDim * (isLandscape ? 0.17 : 0.15)
            let btnHit = btnVisual + 24
            
            let dpadVisual = minDim * (isLandscape ? 0.40 : 0.35)
            let dpadHit = dpadVisual + 40
            
            let startVisualW = minDim * 0.22
            let startVisualH = minDim * 0.11
            
            let buttonSpacing = btnVisual * (isLandscape ? 1.3 : 1.15)

            // Compute exact Centers guaranteeing no overlaps and strict safe area adherence
            let centers: (dpad: CGPoint, a: CGPoint, b: CGPoint, c: CGPoint, start: CGPoint) = {
                if isLandscape {
                    let padX: CGFloat = 16
                    let padY: CGFloat = 16
                    
                    // DPad anchors to Bottom-Left
                    let dpadX = safeLeft + padX + (dpadHit / 2)
                    let dpadY = h - safeBottom - padY - (dpadHit / 2)
                    
                    // Action Buttons anchor to Bottom-Right
                    // We anchor C (top-right most button) to the right edge
                    let cX = w - safeRight - padX - (btnHit / 2)
                    // We anchor A (bottom-left most button) to the bottom edge
                    let aY = h - safeBottom - padY - (btnHit / 2)
                    
                    // B is exactly in between A and C diagonally
                    let aX = cX - (2 * buttonSpacing)
                    let cY = aY - buttonSpacing
                    
                    let bX = cX - buttonSpacing
                    let bY = aY - (buttonSpacing * 0.5)
                    
                    let startX = w / 2
                    let startY = h - safeBottom - 16 - (startVisualH / 2)
                    
                    return (
                        dpad: CGPoint(x: dpadX, y: dpadY),
                        a: CGPoint(x: aX, y: aY),
                        b: CGPoint(x: bX, y: bY),
                        c: CGPoint(x: cX, y: cY),
                        start: CGPoint(x: startX, y: startY)
                    )
                } else {
                    // Portrait Mode
                    let padBottom = max(safeBottom + 16, 24)
                    
                    let startX = w / 2
                    let startY = h - padBottom - (startVisualH / 2)
                    
                    let controlsBaseY = startY - (startVisualH / 2) - 24
                    
                    // DPad anchors to left
                    let dpadX = safeLeft + 16 + (dpadHit / 2)
                    let dpadY = controlsBaseY - (dpadHit / 2)
                    
                    // Action buttons anchor to right
                    let cX = w - safeRight - 16 - (btnHit / 2)
                    let aY = controlsBaseY - (btnHit / 2)
                    let cY = aY - buttonSpacing
                    
                    let aX = cX - (2 * buttonSpacing)
                    let bX = cX - buttonSpacing
                    let bY = aY - (buttonSpacing * 0.5)
                    
                    return (
                        dpad: CGPoint(x: dpadX, y: dpadY),
                        a: CGPoint(x: aX, y: aY),
                        b: CGPoint(x: bX, y: bY),
                        c: CGPoint(x: cX, y: cY),
                        start: CGPoint(x: startX, y: startY)
                    )
                }
            }()

            ZStack(alignment: .topLeading) {
                // D-Pad
                dpadArea(visualSize: dpadVisual, hitSize: dpadHit)
                    .position(centers.dpad)
                
                // A B C Buttons
                let bgColor = Color(red: 0, green: 71/255, blue: 171/255) // #0047AB
                let borderColor = Color(red: 100/255, green: 181/255, blue: 246/255) // #64B5F6
                
                actionButton("A", color: bgColor, borderColor: borderColor, visualSize: btnVisual, hitSize: btnHit) { engine.setButton(ID_Y, pressed: $0) }
                    .position(centers.a)
                
                actionButton("B", color: bgColor, borderColor: borderColor, visualSize: btnVisual, hitSize: btnHit) { engine.setButton(ID_B, pressed: $0) }
                    .position(centers.b)
                
                actionButton("C", color: bgColor, borderColor: borderColor, visualSize: btnVisual, hitSize: btnHit) { engine.setButton(ID_A, pressed: $0) }
                    .position(centers.c)
                
                // START Button
                startButton(visualWidth: startVisualW, visualHeight: startVisualH, hitWidth: startVisualW + 40, hitHeight: startVisualH + 40)
                    .position(centers.start)
            }
        }
    }
    
    private func dpadArea(visualSize: CGFloat, hitSize: CGFloat) -> some View {
        MultiTouchDPad { up, down, left, right in
            engine.setButton(ID_UP, pressed: up)
            engine.setButton(ID_DOWN, pressed: down)
            engine.setButton(ID_LEFT, pressed: left)
            engine.setButton(ID_RIGHT, pressed: right)
        }
        .frame(width: hitSize, height: hitSize)
        .background(
            ZStack {
                // Base Circle (Frosted Glass D-Pad Base)
                Circle()
                    .fill(Color(red: 18/255, green: 19/255, blue: 26/255).opacity(0.44))
                    .frame(width: visualSize, height: visualSize)
                    .overlay(
                        Circle().stroke(Color(red: 168/255, green: 199/255, blue: 250/255).opacity(0.31), lineWidth: 2)
                    )
                
                // Center Thumb Hub
                Circle()
                    .fill(Color.white.opacity(0.19))
                    .frame(width: visualSize * 0.31, height: visualSize * 0.31)
                
                // Directional Arrows
                let offset = visualSize * 0.32
                let iconSize = visualSize * 0.14
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
                        Circle().stroke(borderColor.opacity(0.8), lineWidth: 2)
                    )
                
                Text(label)
                    .font(.system(size: visualSize * 0.35, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        )
    }
    
    private func startButton(visualWidth: CGFloat, visualHeight: CGFloat, hitWidth: CGFloat, hitHeight: CGFloat) -> some View {
        MultiTouchButton { isPressed in
            engine.setButton(ID_START, pressed: isPressed)
        }
        .frame(width: hitWidth, height: hitHeight)
        .background(
            ZStack {
                Capsule()
                    .fill(Color(white: 0.13).opacity(0.4))
                    .frame(width: visualWidth, height: visualHeight)
                    .overlay(
                        Capsule().stroke(Color(white: 0.88).opacity(0.6), lineWidth: 1.5)
                    )
                
                Text("START")
                    .font(.system(size: visualHeight * 0.35, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(white: 0.93))
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
