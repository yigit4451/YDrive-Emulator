import SwiftUI
import GameController

struct EmulatorView: View {
    let game: GameItem
    @Environment(\.dismiss) private var dismiss
    @State private var isControllerConnected = false
    @State private var buttonStates = ButtonState()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ── Game render surface placeholder ──
            Rectangle()
                .fill(Color.black)
                .overlay(
                    Text("Emulator Core Output")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.1))
                )

            // ── On-screen controls ──
            if !isControllerConnected {
                VStack {
                    Spacer()
                    OnScreenControlsView(buttonStates: $buttonStates)
                        .padding(.bottom, 48)
                }
            }

            // ── Top Bar ──
            VStack {
                HStack {
                    Button {
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
                        .padding(.trailing, 64) // balance the layout
                    
                    Spacer()
                }
                Spacer()
            }
        }
        .statusBarHidden(true)
        .onAppear { observeControllers() }
        .onDisappear { NotificationCenter.default.removeObserver(self) }
    }

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
        HStack(alignment: .bottom) {
            // D-Pad
            DPadView(
                onUp: { buttonStates.up = $0 },
                onDown: { buttonStates.down = $0 },
                onLeft: { buttonStates.left = $0 },
                onRight: { buttonStates.right = $0 }
            )
            .padding(.leading, 32)

            Spacer()

            // Action buttons
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    actionButton("C", color: .yellow) { buttonStates.c = $0 }
                    actionButton("B", color: .blue)   { buttonStates.b = $0 }
                    actionButton("A", color: .red)    { buttonStates.a = $0 }
                }
                HStack {
                    Spacer()
                    actionButton("START", color: .white, size: 64) { buttonStates.start = $0 }
                    Spacer()
                }
            }
            .padding(.trailing, 32)
        }
    }

    private func actionButton(
        _ label: String,
        color: Color,
        size: CGFloat = 56,
        onPress: @escaping (Bool) -> Void
    ) -> some View {
        ZStack {
            Circle()
                .applyLiquidGlassCircle()
                .frame(width: size, height: size)
                .overlay(
                    Circle().stroke(color.opacity(0.3), lineWidth: 1)
                )
            
            Text(label)
                .font(.system(size: label.count > 1 ? 14 : 20, weight: .bold, design: .rounded))
                .foregroundStyle(color.opacity(0.8))
        }
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

    var body: some View {
        ZStack {
            // Vertical bar
            Capsule()
                .applyLiquidGlassCapsule()
                .frame(width: 52, height: 160)
            
            // Horizontal bar
            Capsule()
                .applyLiquidGlassCapsule()
                .frame(width: 160, height: 52)

            // Arrows
            Group {
                dpadArrow("chevron.up", offset: CGSize(width: 0, height: -52)) { onUp($0) }
                dpadArrow("chevron.down", offset: CGSize(width: 0, height: 52)) { onDown($0) }
                dpadArrow("chevron.left", offset: CGSize(width: -52, height: 0)) { onLeft($0) }
                dpadArrow("chevron.right", offset: CGSize(width: 52, height: 0)) { onRight($0) }
            }
        }
        .frame(width: 160, height: 160)
    }

    private func dpadArrow(
        _ icon: String,
        offset: CGSize,
        onPress: @escaping (Bool) -> Void
    ) -> some View {
        Image(systemName: icon)
            .font(.title2.weight(.bold))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 52, height: 52)
            .offset(offset)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress(true) }
                    .onEnded   { _ in onPress(false) }
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
