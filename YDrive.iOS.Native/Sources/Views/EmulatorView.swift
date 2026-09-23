import SwiftUI
import GameController
import Photos
import os

private let emulatorLog = Logger(subsystem: "com.yigit.ydrive", category: "EmulatorView")

struct EmulatorView: View {
    let game: GameItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showingGameDetail = false
    @State private var isControllerConnected = false
    @StateObject private var engine = LibretroEmulatorEngine()
    @State private var isTopBarVisible = false
    @State private var isSaveManagerPresented = false
    @State private var showingBiosAlert = false
    @State private var showFlash = false

    @AppStorage("showFPS")       private var showFPS       = false
    @AppStorage("audioEnabled")  private var audioEnabled  = true
    @AppStorage("videoFilter")   private var videoFilter   = "Off"
    @AppStorage("hapticFeedback") private var hapticFeedback = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                // ── Game render surface ──────────────────────────────────────
                if engine.coreAvailable {
                    MetalEmulatorView(engine: engine, videoFilter: videoFilter)
                        .ignoresSafeArea()
                        .overlay(
                            Group {
                                if showFPS {
                                    Text(String(format: "FPS: %.1f", engine.currentFPS))
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(.green)
                                        .padding(6)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(4)
                                        .padding(.top, isTopBarVisible ? 60 : 10)
                                        .padding(.leading, 10)
                                        .allowsHitTesting(false)
                                }
                            }
                            , alignment: .topLeading
                        )
                } else if let errorMsg = engine.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.yellow)
                        Text(NSLocalizedString("emulator.core_unavailable", comment: ""))
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    ProgressView().tint(.white)
                }

                // ── On-screen controls ───────────────────────────────────────
                if !isControllerConnected {
                    OnScreenControlsView(engine: engine)
                        .ignoresSafeArea()
                }

                // ── Screenshot flash overlay ─────────────────────────────────
                if showFlash {
                    Color.white
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // ── Floating collapse button ─────────────────────────────────
                if !isTopBarVisible {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation { isTopBarVisible = true }
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
                            .padding(.top, 24)
                        }
                        Spacer()
                    }
                }
            }
            .statusBarHidden(true)
            .toolbar(isTopBarVisible ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingGameDetail = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gamecontroller.fill")
                                .foregroundColor(.blue)
                            Text(game.title)
                                .foregroundColor(.primary)
                        }
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if verticalSizeClass == .regular {
                        // Portrait: Minimal icons
                        HStack(spacing: 16) {
                            Button { engine.setPaused(!engine.isPaused) } label: { Image(systemName: engine.isPaused ? "play.fill" : "pause.fill") }
                            Button { engine.reset(); if engine.isPaused { engine.setPaused(false) } } label: { Image(systemName: "arrow.counterclockwise") }
                            Button(role: .destructive) { engine.stop(); dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.red) }
                            
                            Menu {
                                Button { withAnimation { engine.setPaused(true); isSaveManagerPresented = true; isTopBarVisible = false } } label: { Label(NSLocalizedString("emulator.save_state", comment: ""), systemImage: "tray.and.arrow.down") }
                                Button { quickLoad() } label: { Label(NSLocalizedString("saves.quick_load", comment: ""), systemImage: "tray.and.arrow.up") }
                                Button { takeScreenshot() } label: { Label(NSLocalizedString("emulator.screenshot", comment: ""), systemImage: "camera.fill") }
                                Button { withAnimation { isTopBarVisible = false } } label: { Label("Collapse", systemImage: "chevron.up") }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                        .font(.title3)
                    } else {
                        // Landscape: All icons
                        HStack(spacing: 16) {
                            Button { engine.setPaused(!engine.isPaused) } label: { Image(systemName: engine.isPaused ? "play.fill" : "pause.fill") }
                            Button { withAnimation { engine.setPaused(true); isSaveManagerPresented = true; isTopBarVisible = false } } label: { Image(systemName: "tray.and.arrow.down") }
                            Button { quickLoad() } label: { Image(systemName: "tray.and.arrow.up") }
                            Button { takeScreenshot() } label: { Image(systemName: "camera.fill") }
                            Button { engine.reset(); if engine.isPaused { engine.setPaused(false) } } label: { Image(systemName: "arrow.counterclockwise") }
                            Button(role: .destructive) { engine.stop(); dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.red) }
                            Button { withAnimation { isTopBarVisible = false } } label: { Image(systemName: "chevron.up") }
                        }
                        .font(.title3)
                    }
                }
            }
        }
        .sheet(isPresented: $isSaveManagerPresented) {
            SaveManagerView(engine: engine, gameFileName: game.fileName, isPresented: $isSaveManagerPresented)
        }
        .sheet(isPresented: $showingGameDetail) {
            GameDetailView(game: game, viewModel: nil)
        }
        .alert(NSLocalizedString("emulator.bios_required", comment: ""), isPresented: $showingBiosAlert) {
            Button(NSLocalizedString("emulator.ok", comment: ""), role: .cancel) { dismiss() }
        } message: {
            Text(NSLocalizedString("emulator.bios_message", comment: ""))
        }
        .onAppear {
            engine.isAudioEnabled = audioEnabled
            observeControllers()
            startEmulator()
        }
        .onChange(of: audioEnabled) { newValue in
            engine.isAudioEnabled = newValue
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self)
            engine.stop()
        }
        .defersSystemGestures(on: .bottom)
        .persistentSystemOverlays(.hidden)
    }

    // ── Screenshot ────────────────────────────────────────────────────────────
    private func takeScreenshot() {
        guard let frame = engine.currentFrame else { return }

        // Haptic feedback
        if hapticFeedback {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        // Flash overlay
        withAnimation(.easeOut(duration: 0.15)) { showFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeIn(duration: 0.2)) { showFlash = false }
        }

        // Save to Photos in background to avoid blocking main thread / engine
        Task.detached {
            guard let image = ScreenshotGenerator.generateScreenshotImage(from: frame) else { return }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { return }
            
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                emulatorLog.info("[SCREENSHOT] Saved game frame successfully")
            } catch {
                emulatorLog.error("[SCREENSHOT] Save error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // ── Quick Load ────────────────────────────────────────────────────────────
    private func quickLoad() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let savesDir = docs.appendingPathComponent("Saves", isDirectory: true)
        let safeName = game.fileName.replacingOccurrences(of: "/", with: "_")

        // Find the latest save slot
        var latestSlot: Int? = nil
        var latestDate: Date = .distantPast

        if let files = try? FileManager.default.contentsOfDirectory(atPath: savesDir.path) {
            for file in files {
                guard file.hasPrefix("\(safeName)_slot"), file.hasSuffix(".state") else { continue }
                let numberStr = file
                    .replacingOccurrences(of: "\(safeName)_slot", with: "")
                    .replacingOccurrences(of: ".state", with: "")
                guard let slot = Int(numberStr) else { continue }
                if let attr = try? FileManager.default.attributesOfItem(atPath: savesDir.appendingPathComponent(file).path),
                   let date = attr[.modificationDate] as? Date, date > latestDate {
                    latestDate = date
                    latestSlot = slot
                }
            }
        }

        guard let slot = latestSlot else { return }

        Task {
            let success = await engine.loadState(for: game.fileName, slot: slot)
            if success { engine.setPaused(false) }
        }
    }

    // ── ROM path resolution ───────────────────────────────────────────────────
    private func startEmulator() {
        if game.consoleName == "SEGA CD" && !BiosManager.shared.hasAnySegaCDBios() {
            showingBiosAlert = true
            return
        }
        let romPath = resolveRomPath(for: game.fileName)
        emulatorLog.info("[VIEW] Starting emulator for: \(game.title, privacy: .public)")
        emulatorLog.info("[VIEW] ROM path: \(romPath, privacy: .public)")
        engine.start(romPath: romPath)
    }

    private func resolveRomPath(for fileName: String) -> String {
        if fileName.hasPrefix("/") { return fileName }
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
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect,    object: nil, queue: .main) { _ in check() }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { _ in check() }
    }
}

// MARK: – On-Screen Controls

struct OnScreenControlsView: View {
    @ObservedObject var engine: LibretroEmulatorEngine

    @AppStorage("controllerOpacity")   private var controllerOpacity   = 0.4
    @AppStorage("buttonColorsEnabled") private var buttonColorsEnabled = true
    @AppStorage("hapticFeedback")      private var hapticFeedback      = true
    @AppStorage("controllerLayout")    private var controllerLayout    = "3-Button"
    @AppStorage("buttonSize")          private var buttonSize          = "Normal"

    // RetroPad IDs
    let ID_B:      UInt32 = 0
    let ID_Y:      UInt32 = 1
    let ID_SELECT: UInt32 = 2
    let ID_START:  UInt32 = 3
    let ID_UP:     UInt32 = 4
    let ID_DOWN:   UInt32 = 5
    let ID_LEFT:   UInt32 = 6
    let ID_RIGHT:  UInt32 = 7
    let ID_A:      UInt32 = 8
    let ID_X:      UInt32 = 9
    let ID_L:      UInt32 = 10
    let ID_R:      UInt32 = 11

    private var sizeMultiplier: CGFloat {
        switch buttonSize {
        case "Small": return 0.80
        case "Large": return 1.20
        default:      return 1.00
        }
    }

    private var is6Button: Bool { controllerLayout == "6-Button" }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let isLandscape = w > h

            let safeBottom = geo.safeAreaInsets.bottom
            let safeLeft   = geo.safeAreaInsets.leading
            let safeRight  = geo.safeAreaInsets.trailing

            let minDim = min(w, h)

            let btnVisual   = minDim * (isLandscape ? 0.17 : 0.15) * sizeMultiplier
            let btnHit      = btnVisual + 24
            let btnSmall    = btnVisual * 0.75          // X/Y/Z and MODE
            let btnSmallHit = btnSmall + 20

            let dpadVisual = minDim * (isLandscape ? 0.40 : 0.35) * sizeMultiplier
            let dpadHit    = dpadVisual + 40

            let startVisualW = minDim * 0.22 * sizeMultiplier
            let startVisualH = minDim * 0.11 * sizeMultiplier

            let spacing = btnVisual * (isLandscape ? 1.3 : 1.15)

            // ── Computed centers ──────────────────────────────────────────────
            // ── Computed centers ──────────────────────────────────────────────
            let centers: (dpad: CGPoint, a: CGPoint, b: CGPoint, c: CGPoint, start: CGPoint, mode: CGPoint) = {
                if isLandscape {
                    let padX: CGFloat = 16
                    let padY: CGFloat = 16

                    let dpadX = safeLeft + padX + (dpadHit / 2)
                    let dpadY = h - safeBottom - padY - (dpadHit / 2)
                    let dpadCenter = CGPoint(x: dpadX, y: dpadY)

                    let cX = w - safeRight - padX - (btnHit / 2)
                    let aY = h - safeBottom - padY - (btnHit / 2)
                    let aX = cX - (2 * spacing)
                    let cY = aY - spacing
                    let bX = cX - spacing
                    let bY = aY - (spacing * 0.5)

                    let aCenter = CGPoint(x: aX, y: aY)
                    let bCenter = CGPoint(x: bX, y: bY)
                    let cCenter = CGPoint(x: cX, y: cY)

                    let startX = w / 2
                    let startY = h - safeBottom - 16 - (startVisualH / 2)
                    let startCenter = CGPoint(x: startX, y: startY)
                    let modeCenter  = CGPoint(x: startX + startVisualW * 0.8, y: startY)
                    
                    return (dpadCenter, aCenter, bCenter, cCenter, startCenter, modeCenter)
                } else {
                    let padBottom = max(safeBottom + 16, 24)

                    let startX = w / 2
                    let startY = h - padBottom - (startVisualH / 2)
                    let startCenter = CGPoint(x: startX, y: startY)
                    let modeCenter  = CGPoint(x: startX + startVisualW * 0.8, y: startY)

                    let controlsBaseY = startY - (startVisualH / 2) - 24

                    let dpadX = safeLeft + 16 + (dpadHit / 2)
                    let dpadY = controlsBaseY - (dpadHit / 2)
                    let dpadCenter = CGPoint(x: dpadX, y: dpadY)

                    let cX = w - safeRight - 16 - (btnHit / 2)
                    let aY = controlsBaseY - (btnHit / 2)
                    let cY = aY - spacing
                    let aX = cX - (2 * spacing)
                    let bX = cX - spacing
                    let bY = aY - (spacing * 0.5)

                    let aCenter = CGPoint(x: aX, y: aY)
                    let bCenter = CGPoint(x: bX, y: bY)
                    let cCenter = CGPoint(x: cX, y: cY)
                    
                    return (dpadCenter, aCenter, bCenter, cCenter, startCenter, modeCenter)
                }
            }()

            // 6-button upper row (X Y Z sit one row above A B C)
            let xCenter = CGPoint(x: centers.a.x, y: centers.a.y - spacing)
            let yCenter = CGPoint(x: centers.b.x, y: centers.b.y - spacing)
            let zCenter = CGPoint(x: centers.c.x, y: centers.c.y - spacing)

            // Colors
            let defaultBg     = Color(red: 0, green: 71/255, blue: 171/255)
            let defaultBorder = Color(red: 100/255, green: 181/255, blue: 246/255)

            let colorA = buttonColorsEnabled ? Color.red    : defaultBg
            let colorB = buttonColorsEnabled ? Color.yellow : defaultBg
            let colorC = buttonColorsEnabled ? Color.blue   : defaultBg
            let colorX = buttonColorsEnabled ? Color(red: 0.5, green: 0, blue: 1) : defaultBg
            let colorY = buttonColorsEnabled ? Color.green  : defaultBg
            let colorZ = buttonColorsEnabled ? Color.orange : defaultBg

            ZStack(alignment: .topLeading) {
                // D-Pad
                dpadArea(visualSize: dpadVisual, hitSize: dpadHit)
                    .position(centers.dpad)

                // A B C
                actionButton("A", color: colorA, borderColor: defaultBorder, visualSize: btnVisual, hitSize: btnHit) { press($0, id: ID_Y) }
                    .position(centers.a)
                actionButton("B", color: colorB, borderColor: defaultBorder, visualSize: btnVisual, hitSize: btnHit) { press($0, id: ID_B) }
                    .position(centers.b)
                actionButton("C", color: colorC, borderColor: defaultBorder, visualSize: btnVisual, hitSize: btnHit) { press($0, id: ID_A) }
                    .position(centers.c)

                // X Y Z (6-button only)
                if is6Button {
                    actionButton("X", color: colorX, borderColor: defaultBorder, visualSize: btnSmall, hitSize: btnSmallHit) { press($0, id: ID_X) }
                        .position(xCenter)
                    actionButton("Y", color: colorY, borderColor: defaultBorder, visualSize: btnSmall, hitSize: btnSmallHit) { press($0, id: ID_L) }
                        .position(yCenter)
                    actionButton("Z", color: colorZ, borderColor: defaultBorder, visualSize: btnSmall, hitSize: btnSmallHit) { press($0, id: ID_R) }
                        .position(zCenter)
                }

                // START + MODE
                startButton(label: "START", visualWidth: startVisualW, visualHeight: startVisualH,
                            hitWidth: startVisualW + 40, hitHeight: startVisualH + 40) { press($0, id: ID_START) }
                    .position(centers.start)

                smallButton(label: "MODE", visualWidth: startVisualW * 0.7, visualHeight: startVisualH,
                            hitWidth: startVisualW * 0.7 + 32, hitHeight: startVisualH + 32) { press($0, id: ID_SELECT) }
                    .position(centers.mode)
            }
        }
        .opacity(controllerOpacity)
    }

    private func press(_ isPressed: Bool, id: UInt32) {
        if isPressed && hapticFeedback {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        engine.setButton(id, pressed: isPressed)
    }

    private func dpadArea(visualSize: CGFloat, hitSize: CGFloat) -> some View {
        MultiTouchDPad { up, down, left, right in
            if (up || down || left || right) && hapticFeedback {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            engine.setButton(ID_UP,    pressed: up)
            engine.setButton(ID_DOWN,  pressed: down)
            engine.setButton(ID_LEFT,  pressed: left)
            engine.setButton(ID_RIGHT, pressed: right)
        }
        .frame(width: hitSize, height: hitSize)
        .background(
            ZStack {
                Circle()
                    .fill(Color(red: 18/255, green: 19/255, blue: 26/255).opacity(0.44))
                    .frame(width: visualSize, height: visualSize)
                    .overlay(Circle().stroke(Color(red: 168/255, green: 199/255, blue: 250/255).opacity(0.31), lineWidth: 2))
                Circle()
                    .fill(Color.white.opacity(0.19))
                    .frame(width: visualSize * 0.31, height: visualSize * 0.31)

                let offset    = visualSize * 0.32
                let iconSize  = visualSize * 0.14
                let iconColor = Color(red: 240/255, green: 244/255, blue: 249/255)
                Image(systemName: "arrowtriangle.up.fill")    .font(.system(size: iconSize)).foregroundStyle(iconColor).offset(y: -offset)
                Image(systemName: "arrowtriangle.down.fill")  .font(.system(size: iconSize)).foregroundStyle(iconColor).offset(y:  offset)
                Image(systemName: "arrowtriangle.left.fill")  .font(.system(size: iconSize)).foregroundStyle(iconColor).offset(x: -offset)
                Image(systemName: "arrowtriangle.right.fill") .font(.system(size: iconSize)).foregroundStyle(iconColor).offset(x:  offset)
            }
        )
    }

    private func actionButton(
        _ label: String, color: Color, borderColor: Color,
        visualSize: CGFloat, hitSize: CGFloat,
        onPress: @escaping (Bool) -> Void
    ) -> some View {
        MultiTouchButton { isPressed in onPress(isPressed) }
            .frame(width: hitSize, height: hitSize)
            .background(
                ZStack {
                    Circle()
                        .fill(color.opacity(0.4))
                        .frame(width: visualSize, height: visualSize)
                        .overlay(Circle().stroke(borderColor.opacity(0.8), lineWidth: 2))
                    Text(label)
                        .font(.system(size: visualSize * 0.35, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            )
    }

    private func startButton(
        label: String,
        visualWidth: CGFloat, visualHeight: CGFloat,
        hitWidth: CGFloat, hitHeight: CGFloat,
        onPress: @escaping (Bool) -> Void
    ) -> some View {
        MultiTouchButton { isPressed in onPress(isPressed) }
            .frame(width: hitWidth, height: hitHeight)
            .background(
                ZStack {
                    Capsule()
                        .fill(Color(white: 0.13).opacity(0.4))
                        .frame(width: visualWidth, height: visualHeight)
                        .overlay(Capsule().stroke(Color(white: 0.88).opacity(0.6), lineWidth: 1.5))
                    Text(label)
                        .font(.system(size: visualHeight * 0.35, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(white: 0.93))
                }
            )
    }

    private func smallButton(
        label: String,
        visualWidth: CGFloat, visualHeight: CGFloat,
        hitWidth: CGFloat, hitHeight: CGFloat,
        onPress: @escaping (Bool) -> Void
    ) -> some View {
        MultiTouchButton { isPressed in onPress(isPressed) }
            .frame(width: hitWidth, height: hitHeight)
            .background(
                ZStack {
                    Capsule()
                        .fill(Color(white: 0.10).opacity(0.35))
                        .frame(width: visualWidth, height: visualHeight)
                        .overlay(Capsule().stroke(Color(white: 0.75).opacity(0.5), lineWidth: 1))
                    Text(label)
                        .font(.system(size: visualHeight * 0.30, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.80))
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
