import SwiftUI
import GameController

/// Emulator canvas view.
/// Actual libretro bridging / C interop goes here.
/// This stub shows the on-screen controller overlay.
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
                        .foregroundStyle(.white.opacity(0.1))
                        .font(.caption)
                )

            // ── On-screen controls (hidden when MFi/GCController connected) ──
            if !isControllerConnected {
                VStack {
                    Spacer()
                    OnScreenControlsView(buttonStates: $buttonStates)
                        .padding(.bottom, 20)
                }
            }

            // ── Dismiss button ──
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(12)
                    }
                    Spacer()
                    Text(game.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.trailing, 50)
                }
                Spacer()
            }
        }
        .statusBarHidden(true)
        .onAppear { observeControllers() }
        .onDisappear { NotificationCenter.default.removeObserver(self) }
    }

    private func observeControllers() {
        let check = { [self] in
            isControllerConnected = !GCController.controllers().isEmpty
        }
        check()
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main) { _ in check() }
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main) { _ in check() }
    }
}

// MARK: – On-Screen D-Pad + Buttons
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
            .frame(width: 140, height: 140)
            .padding(.leading, 24)

            Spacer()

            // Action buttons
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    actionButton("C", color: .yellow) { buttonStates.c = $0 }
                    actionButton("B", color: .blue)   { buttonStates.b = $0 }
                    actionButton("A", color: .red)    { buttonStates.a = $0 }
                }
                HStack {
                    Spacer()
                    actionButton("START", color: .white.opacity(0.8), size: 56) { buttonStates.start = $0 }
                    Spacer()
                }
            }
            .padding(.trailing, 24)
        }
    }

    private func actionButton(
        _ label: String,
        color: Color,
        size: CGFloat = 52,
        onPress: @escaping (Bool) -> Void
    ) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 2))
                .frame(width: size, height: size)
            Text(label)
                .font(.system(size: label.count > 1 ? 11 : 16, weight: .bold))
                .foregroundStyle(color)
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
            // Horizontal bar
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                .frame(width: 140, height: 46)

            // Vertical bar
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                .frame(width: 46, height: 140)

            // Arrows
            Group {
                dpadArrow("chevron.up",    offset: CGSize(width: 0, height: -44)) { onUp($0) }
                dpadArrow("chevron.down",  offset: CGSize(width: 0, height: 44))  { onDown($0) }
                dpadArrow("chevron.left",  offset: CGSize(width: -44, height: 0)) { onLeft($0) }
                dpadArrow("chevron.right", offset: CGSize(width: 44, height: 0))  { onRight($0) }
            }
        }
    }

    private func dpadArrow(
        _ icon: String,
        offset: CGSize,
        onPress: @escaping (Bool) -> Void
    ) -> some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 36, height: 36)
            .offset(offset)
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
