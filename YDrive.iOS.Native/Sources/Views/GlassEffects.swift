import SwiftUI

// MARK: - iOS 26 Liquid Glass Custom Implementations

/// A view modifier that applies the signature iOS 26 Liquid Glass effect to any shape.
struct GlassEffectModifier<S: Shape>: ViewModifier {
    let shape: S
    let intensity: Double
    
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(shape)
            .overlay(
                shape
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.05), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
    }
}

extension View {
    /// Applies an iOS 26 style liquid glass effect within the given shape.
    func glassEffect<S: Shape>(in shape: S, intensity: Double = 1.0) -> some View {
        self.modifier(GlassEffectModifier(shape: shape, intensity: intensity))
    }
}

// MARK: - iOS 26 Glass Button Style

struct GlassButtonStyle: ButtonStyle {
    private var tintColor: Color = .blue
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(tintColor ?? .blue)
                    .opacity(configuration.isPressed ? 0.3 : 0.2)
            )
            .glassEffect(in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    /// The iOS 26 liquid glass button style.
    static var glass: GlassButtonStyle {
        GlassButtonStyle()
    }
}
