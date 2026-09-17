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
                        .foregroundStyle(.white.opacity(0.1))
                        .font(.caption)
                )

            // ── On-screen controls ──
            if !isControllerConnected {
                VStack {
                    Spacer()
                    OnScreenControlsView(buttonStates: $buttonStates)
                        .padding(.bottom, 32)
                }
            }

            // ── Dismiss & Title Bar ──
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                    }
                    .glassEffect(in: Circle())
                    .padding(16)
                    
                    Spacer()
                    
                    Text(game.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassEffect(in: Capsule())
                        .padding(.trailing, 60) // balance the layout
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

// MARK: – On-Screen Controls (Liquid Glass)

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
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    actionButton("C", color: .yellow) { buttonStates.c = $0 }
                    actionButton("B", color: .blue)   { buttonStates.b = $0 }
                    actionButton("A", color: .red)    { buttonStates.a = $0 }
                }
                HStack {
                    Spacer()
                    actionButton("START", color: .white, size: 60) { buttonStates.start = $0 }
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
                .fill(color.opacity(0.15))
                .frame(width: size, height: size)
            
            Text(label)
                .font(.system(size: label.count > 1 ? 12 : 18, weight: .black, design: .rounded))
                .foregroundStyle(color)
        }
        // iOS 26 liquid glass button
        .glassEffect(in: Circle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress(true) }
                .onEnded   { _ in onPress(false) }
        )
    }
}

// MARK: – Liquid Glass D-Pad
struct DPadView: View {
    var onUp: (Bool) -> Void
    var onDown: (Bool) -> Void
    var onLeft: (Bool) -> Void
    var onRight: (Bool) -> Void

    var body: some View {
        ZStack {
            // Cross shape background
            crossShape
                .fill(Color.white.opacity(0.05))
                .frame(width: 150, height: 150)
                // We apply the glass effect to the whole cross
                .glassEffect(in: crossShape)

            // Arrows
            Group {
                dpadArrow("chevron.up", offset: CGSize(width: 0, height: -48)) { onUp($0) }
                dpadArrow("chevron.down", offset: CGSize(width: 0, height: 48)) { onDown($0) }
                dpadArrow("chevron.left", offset: CGSize(width: -48, height: 0)) { onLeft($0) }
                dpadArrow("chevron.right", offset: CGSize(width: 48, height: 0)) { onRight($0) }
            }
        }
        .frame(width: 150, height: 150)
    }
    
    private var crossShape: some Shape {
        // A simple composition of two capsules to form a cross.
        // In real SwiftUI, you'd use a Path for a perfect outline, but for now we'll combine shapes visually.
        // To make the glassEffect outline work properly, we use a single custom shape.
        DPadCrossShape()
    }

    private func dpadArrow(
        _ icon: String,
        offset: CGSize,
        onPress: @escaping (Bool) -> Void
    ) -> some View {
        Image(systemName: icon)
            .font(.system(size: 22, weight: .black))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 48, height: 48)
            .offset(offset)
            .contentShape(Rectangle()) // Make hit area larger
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress(true) }
                    .onEnded   { _ in onPress(false) }
            )
    }
}

/// Custom shape for the D-Pad to apply the glass stroke perfectly
struct DPadCrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let armWidth = width * 0.35
        
        let minX = (width - armWidth) / 2
        let maxX = minX + armWidth
        let minY = (height - armWidth) / 2
        let maxY = minY + armWidth
        let radius = armWidth / 2
        
        // Top arm
        path.move(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: minX, y: radius))
        path.addArc(center: CGPoint(x: width/2, y: radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: maxX, y: minY))
        
        // Right arm
        path.addLine(to: CGPoint(x: width - radius, y: minY))
        path.addArc(center: CGPoint(x: width - radius, y: height/2), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: maxX, y: maxY))
        
        // Bottom arm
        path.addLine(to: CGPoint(x: maxX, y: height - radius))
        path.addArc(center: CGPoint(x: width/2, y: height - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: minX, y: maxY))
        
        // Left arm
        path.addLine(to: CGPoint(x: radius, y: maxY))
        path.addArc(center: CGPoint(x: radius, y: height/2), radius: radius, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: false)
        path.closeSubpath()
        
        return path
    }
}

#Preview {
    EmulatorView(game: GameItem(
        title: "Sonic the Hedgehog",
        consoleName: "SEGA Genesis",
        fileName: "sonic.bin"
    ))
}
