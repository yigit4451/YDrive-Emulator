import SwiftUI
import GameController
import Photos
import os

private let emulatorLog = Logger(subsystem: "com.yigit.ydrive", category: "EmulatorView")

struct EmulatorView: View {
    let game: GameItem
    @ObservedObject var viewModel: GameLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showingGameDetail = false
    @State private var isControllerConnected = false
    @State private var controllerObservers: [NSObjectProtocol] = []
    @StateObject private var engine = LibretroEmulatorEngine()
    @State private var isTopBarVisible = false
    @State private var isSaveManagerPresented = false
    @State private var showingBiosAlert = false
    @State private var showFlash = false

    @AppStorage("showFPS")             private var showFPS             = false
    @AppStorage("audioEnabled")        private var audioEnabled        = true
    @AppStorage("videoFilter")         private var videoFilter         = "Off"
    @AppStorage("hapticFeedback")      private var hapticFeedback      = true
    @AppStorage("m30MappingEnabled")   private var m30MappingEnabled   = false
    @AppStorage("allRightShoulders")   private var allRightShoulders   = false
    @AppStorage("appTheme")            private var appTheme            = "system"

    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "dark":  return .dark
        case "light": return .light
        default:      return nil
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let isLandscape = w > h

                ZStack {
                    Color.black.ignoresSafeArea()

                    // ── Game render surface ──────────────────────────────────────
                    if engine.coreAvailable {
                        gameRenderSurface(width: w, height: h, isLandscape: isLandscape)
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
                        OnScreenControlsView(engine: engine, consoleName: game.consoleName)
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
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                }
                                .padding(16)
                                .padding(.top, isLandscape ? 16 : max(stableSafeTop, 16))
                            }
                            Spacer()
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .statusBarHidden(true)
            .defersSystemGestures(on: .all)
            .toolbar(isTopBarVisible ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: titleMaxWidth, alignment: .leading)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if verticalSizeClass == .regular {
                        // Portrait: Minimal icons
                        HStack(spacing: 16) {
                            Button { engine.setPaused(!engine.isPaused) } label: { Image(systemName: engine.isPaused ? "play.fill" : "pause.fill") }
                            Button { withAnimation { isTopBarVisible = false } } label: { Image(systemName: "chevron.up") }
                            Button(role: .destructive) { engine.stop(); dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.red) }
                            
                            Menu {
                                Button {
                                    engine.reset()
                                    if engine.isPaused { engine.setPaused(false) }
                                } label: {
                                    Label {
                                        Text(NSLocalizedString("emulator.reset", comment: ""))
                                            .font(.body.weight(.bold))
                                            .foregroundStyle(.white)
                                    } icon: {
                                        Image(uiImage: whiteMenuIcon("arrow.counterclockwise"))
                                    }
                                }
                                Button {
                                    engine.setPaused(true)
                                    isSaveManagerPresented = true
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isTopBarVisible = false
                                    }
                                } label: {
                                    Label {
                                        Text(NSLocalizedString("emulator.save_state", comment: ""))
                                            .font(.body.weight(.bold))
                                            .foregroundStyle(.white)
                                    } icon: {
                                        Image(uiImage: whiteMenuIcon("tray.and.arrow.down.fill"))
                                    }
                                }
                                Button {
                                    takeScreenshot()
                                } label: {
                                    Label {
                                        Text(NSLocalizedString("emulator.screenshot", comment: ""))
                                            .font(.body.weight(.bold))
                                            .foregroundStyle(.white)
                                    } icon: {
                                        Image(uiImage: whiteMenuIcon("camera.fill"))
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.white)
                            }
                            .tint(.white)
                            .foregroundStyle(.white)
                            .environment(\.colorScheme, .dark)
                        }
                        .font(.title3)
                        .tint(.white)
                        .foregroundStyle(.white)
                        .fixedSize()
                    } else {
                        // Landscape: All icons
                        HStack(spacing: 16) {
                            Button { engine.setPaused(!engine.isPaused) } label: { Image(systemName: engine.isPaused ? "play.fill" : "pause.fill") }
                            Button {
                                engine.setPaused(true)
                                isSaveManagerPresented = true
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isTopBarVisible = false
                                }
                            } label: { Image(systemName: "tray.and.arrow.down") }
                            Button { takeScreenshot() } label: { Image(systemName: "camera.fill") }
                            Button { engine.reset(); if engine.isPaused { engine.setPaused(false) } } label: { Image(systemName: "arrow.counterclockwise") }
                            Button { withAnimation { isTopBarVisible = false } } label: { Image(systemName: "chevron.up") }
                            Button(role: .destructive) { engine.stop(); dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.red) }
                        }
                        .font(.title3)
                        .tint(.white)
                        .foregroundStyle(.white)
                        .fixedSize()
                    }
                }
            }
        }
        .sheet(isPresented: $isSaveManagerPresented) {
            NavigationStack {
                SaveManagerView(engine: engine, gameFileName: game.fileName, isPresented: $isSaveManagerPresented)
            }
            .presentationDetents([.large])
            .presentationBackground(.ultraThinMaterial)
            .preferredColorScheme(colorScheme)
        }
        .sheet(isPresented: $showingGameDetail) {
            GameDetailView(initialGame: game, viewModel: viewModel, isPresentedFromEmulator: true)
                .preferredColorScheme(colorScheme)
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
        .onChange(of: isSaveManagerPresented) { isPresented in
            if !isPresented {
                withAnimation {
                    isTopBarVisible = true
                }
            }
        }
        .onDisappear {
            removeControllerObservers()
            engine.stop()
        }
        .defersSystemGestures(on: .all)
        .preferredColorScheme(.dark)
    }

    @MainActor
    private var stableSafeTop: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? scenes.first as? UIWindowScene
        let top = windowScene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top
            ?? windowScene?.windows.first?.safeAreaInsets.top
        if let top = top, top > 0 {
            return top
        }
        return 47
    }

    @ViewBuilder
    private func gameRenderSurface(width: CGFloat, height: CGFloat, isLandscape: Bool) -> some View {
        if isLandscape {
            MetalEmulatorView(engine: engine, videoFilter: videoFilter)
                .ignoresSafeArea()
                .overlay(fpsOverlay(isLandscape: true), alignment: .topLeading)
        } else {
            let safeTop = stableSafeTop
            let aspect = CGFloat(engine.aspectRatio > 0.01 ? engine.aspectRatio : 4.0/3.0)
            let topClearance = safeTop + 54
            let controlsTop = height * 0.58
            let availableH = max(100, controlsTop - topClearance - 8)
            let maxGameH = min((height - safeTop) * 0.48, availableH)
            let gameW = min(width, maxGameH * aspect)
            let gameH = gameW / aspect
            let gameY = (topClearance + controlsTop) / 2

            MetalEmulatorView(engine: engine, videoFilter: videoFilter)
                .frame(width: gameW, height: gameH)
                .overlay(fpsOverlay(isLandscape: false), alignment: .topLeading)
                .position(x: width / 2, y: gameY)
        }
    }

    // Max width of the top-bar title so it truncates instead of pushing the buttons into the overflow menu.
    private var titleMaxWidth: CGFloat {
        let width = UIScreen.main.bounds.width
        let reserved: CGFloat = verticalSizeClass == .regular ? 310 : 430
        return max(90, width - reserved)
    }

    // Helper for crisp, bold, solid white icons in UIMenu
    private func whiteMenuIcon(_ name: String) -> UIImage {
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        return UIImage(systemName: name, withConfiguration: cfg)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) ?? UIImage()
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
        let gameURL = URL(fileURLWithPath: game.fileName)
        let gameDir = gameURL.deletingLastPathComponent()

        var latestSlot: Int? = nil
        var latestDate: Date = .distantPast

        // Check in game's directory
        if let files = try? FileManager.default.contentsOfDirectory(atPath: gameDir.path) {
            for file in files {
                guard file.hasPrefix("slot"), file.hasSuffix(".state") else { continue }
                let numberStr = file
                    .replacingOccurrences(of: "slot", with: "")
                    .replacingOccurrences(of: ".state", with: "")
                guard let slot = Int(numberStr) else { continue }
                if let attr = try? FileManager.default.attributesOfItem(atPath: gameDir.appendingPathComponent(file).path),
                   let date = attr[.modificationDate] as? Date, date > latestDate {
                    latestDate = date
                    latestSlot = slot
                }
            }
        }

        // Also check legacy Saves folder
        if latestSlot == nil, let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let savesDir = docs.appendingPathComponent("Saves", isDirectory: true)
            let safeName = game.fileName.replacingOccurrences(of: "/", with: "_")
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
        // 1. If absolute path is still valid, use it
        if FileManager.default.fileExists(atPath: fileName) {
            return fileName
        }

        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return fileName
        }

        let name = (fileName as NSString).lastPathComponent

        // 2. Search recursively in ROM's folder
        let romsDir = docs.appendingPathComponent("ROM's", isDirectory: true)
        if let enumerator = FileManager.default.enumerator(at: romsDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == name {
                    return fileURL.path
                }
            }
        }

        // 3. Check directly in docs
        let candidate = docs.appendingPathComponent(name).path
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }

        if fileName.hasPrefix("/") { return fileName }
        return docs.appendingPathComponent(fileName).path
    }

    // ── Controller observation ────────────────────────────────────────────────
    private func observeControllers() {
        removeControllerObservers()

        let updateControllers: @Sendable () -> Void = {
            Task { @MainActor in
                let controllers = GCController.controllers()
                let physical = controllers.filter { $0.extendedGamepad != nil }
                self.isControllerConnected = !physical.isEmpty
                for controller in physical {
                    self.setupGamepad(controller)
                }
            }
        }

        updateControllers()

        let connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { _ in
            updateControllers()
        }

        let disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { _ in
            updateControllers()
        }

        controllerObservers = [connectObserver, disconnectObserver]
    }

    private func removeControllerObservers() {
        for observer in controllerObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        controllerObservers.removeAll()
    }

    private func setupGamepad(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }

        // DualSense Lightbar & Touchpad
        if let dualSense = gamepad as? GCDualSenseGamepad {
            controller.light?.color = GCColor(red: 0.0, green: 0.48, blue: 1.0) // YDrive Blue
            dualSense.touchpadButton.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(2, pressed: pressed) // Genesis MODE
            }
        } else {
            controller.light?.color = GCColor(red: 0.0, green: 0.48, blue: 1.0)
        }

        let isSMS = game.consoleName == "SEGA Master System" || game.consoleName == "SEGA Game Gear"

        // Directional State: blend D-pad and Left Analog Stick so neither overrides the other
        final class DirectionState: @unchecked Sendable {
            var dpadUp = false, dpadDown = false, dpadLeft = false, dpadRight = false
            var stickUp = false, stickDown = false, stickLeft = false, stickRight = false
        }
        let dir = DirectionState()

        // D-Pad
        gamepad.dpad.up.valueChangedHandler = { [weak engine] _, _, pressed in
            dir.dpadUp = pressed
            engine?.setButton(4, pressed: dir.dpadUp || dir.stickUp)
        }
        gamepad.dpad.down.valueChangedHandler = { [weak engine] _, _, pressed in
            dir.dpadDown = pressed
            engine?.setButton(5, pressed: dir.dpadDown || dir.stickDown)
        }
        gamepad.dpad.left.valueChangedHandler = { [weak engine] _, _, pressed in
            dir.dpadLeft = pressed
            engine?.setButton(6, pressed: dir.dpadLeft || dir.stickLeft)
        }
        gamepad.dpad.right.valueChangedHandler = { [weak engine] _, _, pressed in
            dir.dpadRight = pressed
            engine?.setButton(7, pressed: dir.dpadRight || dir.stickRight)
        }

        // Left Analog Stick (Thumbstick support for DualSense & Xbox)
        let deadzone: Float = 0.35
        gamepad.leftThumbstick.valueChangedHandler = { [weak engine] _, xValue, yValue in
            let newUp = yValue > deadzone
            let newDown = yValue < -deadzone
            let newLeft = xValue < -deadzone
            let newRight = xValue > deadzone

            if newUp != dir.stickUp {
                dir.stickUp = newUp
                engine?.setButton(4, pressed: dir.dpadUp || dir.stickUp)
            }
            if newDown != dir.stickDown {
                dir.stickDown = newDown
                engine?.setButton(5, pressed: dir.dpadDown || dir.stickDown)
            }
            if newLeft != dir.stickLeft {
                dir.stickLeft = newLeft
                engine?.setButton(6, pressed: dir.dpadLeft || dir.stickLeft)
            }
            if newRight != dir.stickRight {
                dir.stickRight = newRight
                engine?.setButton(7, pressed: dir.dpadRight || dir.stickRight)
            }
        }

        // Action Buttons
        if isSMS {
            // Master System & Game Gear: Button 1 (ID 0) and Button 2 (ID 8)
            // Map both Cross/Square and Circle/Triangle pairs for comfortable 2-button play
            gamepad.buttonA.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(0, pressed: pressed) // SMS Button 1
            }
            gamepad.buttonX.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(0, pressed: pressed) // SMS Button 1
            }
            gamepad.buttonB.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(8, pressed: pressed) // SMS Button 2
            }
            gamepad.buttonY.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(8, pressed: pressed) // SMS Button 2
            }
            gamepad.leftShoulder.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(0, pressed: pressed)
            }
            gamepad.rightShoulder.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(8, pressed: pressed)
            }
            gamepad.leftTrigger.valueChangedHandler = { [weak engine] _, value, _ in
                engine?.setButton(0, pressed: value > 0.3)
            }
            gamepad.rightTrigger.valueChangedHandler = { [weak engine] _, value, _ in
                engine?.setButton(8, pressed: value > 0.3)
            }
        } else if m30MappingEnabled {
            // 8BitDo M30 Layout
            gamepad.buttonA.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(1, pressed: pressed) // Genesis A
            }
            gamepad.buttonB.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(0, pressed: pressed) // Genesis B
            }
            gamepad.rightShoulder.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(8, pressed: pressed) // Genesis C
            }
            gamepad.buttonX.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(9, pressed: pressed) // Genesis X
            }
            gamepad.buttonY.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(10, pressed: pressed) // Genesis Y
            }
            gamepad.rightTrigger.valueChangedHandler = { [weak engine] _, value, _ in
                engine?.setButton(11, pressed: value > 0.3) // Genesis Z
            }
            gamepad.leftShoulder.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(10, pressed: pressed)
            }
            gamepad.leftTrigger.valueChangedHandler = { [weak engine] _, value, _ in
                engine?.setButton(2, pressed: value > 0.3) // Genesis MODE
            }
        } else if allRightShoulders {
            // All-Right Shoulders Layout (Face A, B, C; RB=Y, RT=Z)
            gamepad.buttonX.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(1, pressed: pressed) // Genesis A
            }
            gamepad.buttonA.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(0, pressed: pressed) // Genesis B
            }
            gamepad.buttonB.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(8, pressed: pressed) // Genesis C
            }
            gamepad.buttonY.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(9, pressed: pressed) // Genesis X
            }
            gamepad.leftShoulder.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(9, pressed: pressed) // Genesis X
            }
            gamepad.rightShoulder.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(10, pressed: pressed) // Genesis Y
            }
            gamepad.rightTrigger.valueChangedHandler = { [weak engine] _, value, _ in
                engine?.setButton(11, pressed: value > 0.3) // Genesis Z
            }
            gamepad.leftTrigger.valueChangedHandler = { [weak engine] _, value, _ in
                engine?.setButton(2, pressed: value > 0.3) // Genesis MODE
            }
        } else {
            // Standard DualSense & Xbox Layout
            // Face: Square/X -> Genesis A, Cross/A -> Genesis B, Circle/B -> Genesis C
            gamepad.buttonX.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(1, pressed: pressed) // Genesis A
            }
            gamepad.buttonA.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(0, pressed: pressed) // Genesis B
            }
            gamepad.buttonB.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(8, pressed: pressed) // Genesis C
            }

            // Top Row / 6-button:
            // Triangle/Y -> Genesis Y
            // L1/LB -> Genesis X
            // R1/RB -> Genesis Z
            gamepad.buttonY.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(10, pressed: pressed) // Genesis Y
            }
            gamepad.leftShoulder.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(9, pressed: pressed) // Genesis X
            }
            gamepad.rightShoulder.valueChangedHandler = { [weak engine] _, _, pressed in
                engine?.setButton(11, pressed: pressed) // Genesis Z
            }

            // L2/LT and R2/RT triggers also provide secondary bindings
            gamepad.leftTrigger.valueChangedHandler = { [weak engine] _, value, _ in
                engine?.setButton(9, pressed: value > 0.3) // Genesis X
            }
            gamepad.rightTrigger.valueChangedHandler = { [weak engine] _, value, _ in
                engine?.setButton(11, pressed: value > 0.3) // Genesis Z
            }
        }

        // Menu / START & Options / MODE
        gamepad.buttonMenu.valueChangedHandler = { [weak engine] _, _, pressed in
            engine?.setButton(3, pressed: pressed) // Genesis START / Pause
        }
        gamepad.buttonOptions?.valueChangedHandler = { [weak engine] _, _, pressed in
            engine?.setButton(2, pressed: pressed) // Genesis MODE
        }
    }
    
    // ── FPS Overlay Helper ───────────────────────────────────────────────────
    private var formattedFPS: String {
        String(format: "FPS: %.1f", engine.currentFPS)
    }
    
    @ViewBuilder
    private func fpsOverlay(isLandscape: Bool) -> some View {
        if showFPS {
            Text(formattedFPS)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.green)
                .padding(6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .padding(.top, (isLandscape && isTopBarVisible) ? 60 : 10)
                .padding(.leading, 10)
                .allowsHitTesting(false)
        }
    }
}

// MARK: – On-Screen Controls

struct OnScreenControlsView: View {
    let engine: LibretroEmulatorEngine
    var consoleName: String = "SEGA Genesis"

    @AppStorage("controllerOpacity")   private var controllerOpacity   = 0.4
    @AppStorage("buttonColorsEnabled") private var buttonColorsEnabled = false
    @AppStorage("hapticFeedback")      private var hapticFeedback      = true
    @AppStorage("controllerLayout")    private var controllerLayout    = "Auto"
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

    private var is2ButtonLayout: Bool {
        if controllerLayout == "Master System" || controllerLayout == "2-Button" { return true }
        if controllerLayout == "Auto" || controllerLayout == "3-Button" {
            return consoleName == "SEGA Master System" || consoleName == "SEGA Game Gear"
        }
        return false
    }

    private var isGameGear: Bool {
        consoleName == "SEGA Game Gear"
    }

    private var is6Button: Bool {
        !is2ButtonLayout && controllerLayout == "6-Button"
    }

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

            // Hit regions for the single UIKit touch surface. They use exactly the same
            // geometry as the visuals below, but touch handling no longer depends on
            // per-button SwiftUI hit-testing.
            let regions: [TouchRegion] = {
                var r: [TouchRegion] = []
                func add(_ kind: TouchRegion.Kind, _ c: CGPoint, _ width: CGFloat, _ height: CGFloat) {
                    r.append(TouchRegion(kind: kind,
                                         rect: CGRect(x: c.x - width / 2, y: c.y - height / 2,
                                                      width: width, height: height)))
                }
                add(.dpad, centers.dpad, dpadHit, dpadHit)
                if self.is2ButtonLayout {
                    add(.button(self.ID_B),     CGPoint(x: centers.b.x, y: centers.a.y), btnHit + 12, btnHit + 12)
                    add(.button(self.ID_A),     CGPoint(x: centers.c.x, y: centers.b.y), btnHit + 12, btnHit + 12)
                    add(.button(self.ID_START), centers.start, startVisualW * 1.15 + 12, startVisualH + 12)
                } else {
                    add(.button(self.ID_Y), centers.a, btnHit + 12, btnHit + 12)
                    add(.button(self.ID_B), centers.b, btnHit + 12, btnHit + 12)
                    add(.button(self.ID_A), centers.c, btnHit + 12, btnHit + 12)
                    if self.is6Button {
                        add(.button(self.ID_X), xCenter, btnSmallHit + 12, btnSmallHit + 12)
                        add(.button(self.ID_L), yCenter, btnSmallHit + 12, btnSmallHit + 12)
                        add(.button(self.ID_R), zCenter, btnSmallHit + 12, btnSmallHit + 12)
                    }
                    add(.button(self.ID_START),  centers.start, startVisualW + 12, startVisualH + 12)
                    add(.button(self.ID_SELECT), centers.mode, startVisualW * 0.7 + 12, startVisualH + 12)
                }
                return r
            }()

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
                // ── Visuals (never intercept touches) ─────────────────────────
                ZStack(alignment: .topLeading) {
                    // D-Pad
                    dpadArea(visualSize: dpadVisual, hitSize: dpadHit)
                        .position(centers.dpad)

                    if is2ButtonLayout {
                        // Master System & Game Gear: Button 1 & 2
                        actionButton(
                            "1",
                            color: buttonColorsEnabled ? Color(red: 225/255, green: 45/255, blue: 57/255) : defaultBg,
                            borderColor: buttonColorsEnabled ? Color(red: 255/255, green: 130/255, blue: 140/255) : defaultBorder,
                            visualSize: btnVisual * 1.08,
                            hitSize: btnHit + 12
                        )
                        .position(CGPoint(x: centers.b.x, y: centers.a.y))

                        actionButton(
                            "2",
                            color: buttonColorsEnabled ? Color(red: 0/255, green: 115/255, blue: 230/255) : defaultBg,
                            borderColor: buttonColorsEnabled ? Color(red: 100/255, green: 181/255, blue: 246/255) : defaultBorder,
                            visualSize: btnVisual * 1.08,
                            hitSize: btnHit + 12
                        )
                        .position(CGPoint(x: centers.c.x, y: centers.b.y))

                        // START / PAUSE
                        startButton(
                            label: isGameGear ? "START" : "PAUSE",
                            visualWidth: startVisualW * 1.15,
                            visualHeight: startVisualH,
                            hitWidth: startVisualW * 1.15 + 40,
                            hitHeight: startVisualH + 40
                        )
                        .position(centers.start)
                    } else {
                        // A B C
                        actionButton("A", color: colorA, borderColor: defaultBorder, visualSize: btnVisual, hitSize: btnHit)
                            .position(centers.a)
                        actionButton("B", color: colorB, borderColor: defaultBorder, visualSize: btnVisual, hitSize: btnHit)
                            .position(centers.b)
                        actionButton("C", color: colorC, borderColor: defaultBorder, visualSize: btnVisual, hitSize: btnHit)
                            .position(centers.c)

                        // X Y Z (6-button only)
                        if is6Button {
                            actionButton("X", color: colorX, borderColor: defaultBorder, visualSize: btnSmall, hitSize: btnSmallHit)
                                .position(xCenter)
                            actionButton("Y", color: colorY, borderColor: defaultBorder, visualSize: btnSmall, hitSize: btnSmallHit)
                                .position(yCenter)
                            actionButton("Z", color: colorZ, borderColor: defaultBorder, visualSize: btnSmall, hitSize: btnSmallHit)
                                .position(zCenter)
                        }

                        // START + MODE
                        startButton(label: "START", visualWidth: startVisualW, visualHeight: startVisualH,
                                    hitWidth: startVisualW + 40, hitHeight: startVisualH + 40)
                            .position(centers.start)

                        smallButton(label: "MODE", visualWidth: startVisualW * 0.7, visualHeight: startVisualH,
                                    hitWidth: startVisualW * 0.7 + 32, hitHeight: startVisualH + 32)
                            .position(centers.mode)
                    }
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .opacity(controllerOpacity)
                .allowsHitTesting(false)

                // ── Single multi-touch UIKit surface that drives the emulator input ──
                TouchControlSurface(regions: regions, hapticEnabled: hapticFeedback) { id, pressed in
                    engine.setButton(id, pressed: pressed)
                }
                .frame(width: w, height: h)
            }
            .frame(width: w, height: h, alignment: .topLeading)
        }
    }

    private func dpadArea(visualSize: CGFloat, hitSize: CGFloat) -> some View {
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
        .frame(width: hitSize, height: hitSize)
    }

    private func actionButton(
        _ label: String, color: Color, borderColor: Color,
        visualSize: CGFloat, hitSize: CGFloat
    ) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.4))
                .frame(width: visualSize, height: visualSize)
                .overlay(Circle().stroke(borderColor.opacity(0.8), lineWidth: 2))
            Text(label)
                .font(.system(size: visualSize * 0.35, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: hitSize, height: hitSize)
    }

    private func startButton(
        label: String,
        visualWidth: CGFloat, visualHeight: CGFloat,
        hitWidth: CGFloat, hitHeight: CGFloat
    ) -> some View {
        ZStack {
            Capsule()
                .fill(Color(white: 0.13).opacity(0.4))
                .frame(width: visualWidth, height: visualHeight)
                .overlay(Capsule().stroke(Color(white: 0.88).opacity(0.6), lineWidth: 1.5))
            Text(label)
                .font(.system(size: visualHeight * 0.35, weight: .bold, design: .rounded))
                .foregroundStyle(Color(white: 0.93))
        }
        .frame(width: hitWidth, height: hitHeight)
    }

    private func smallButton(
        label: String,
        visualWidth: CGFloat, visualHeight: CGFloat,
        hitWidth: CGFloat, hitHeight: CGFloat
    ) -> some View {
        ZStack {
            Capsule()
                .fill(Color(white: 0.10).opacity(0.35))
                .frame(width: visualWidth, height: visualHeight)
                .overlay(Capsule().stroke(Color(white: 0.75).opacity(0.5), lineWidth: 1))
            Text(label)
                .font(.system(size: visualHeight * 0.30, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.80))
        }
        .frame(width: hitWidth, height: hitHeight)
    }
    

}
#Preview {
    EmulatorView(game: GameItem(
        title: "Sonic the Hedgehog",
        consoleName: "SEGA Genesis",
        fileName: "sonic.bin"
    ), viewModel: GameLibraryViewModel())
}
