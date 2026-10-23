import SwiftUI

// MARK: - iOS 26 Liquid Glass Design System Native API

/// Styles for the system-rendered Liquid Glass visual effect.
public enum GlassEffectStyle: Sendable {
    /// Standard system-rendered Liquid Glass effect with natural refraction.
    case regular
    /// Prominent Liquid Glass effect with higher opacity and vibrancy.
    case prominent
    /// Ultra-clear subtle Liquid Glass effect.
    case clear
}

public extension View {
    /// Applies Apple's native system Liquid Glass effect to the view.
    ///
    /// - Parameters:
    ///   - style: The visual prominence of the glass effect. Defaults to `.regular`.
    ///   - shape: The clipping shape for the glass surface.
    @ViewBuilder
    func glassEffect<S: Shape>(_ style: GlassEffectStyle = .regular, in shape: S) -> some View {
        switch style {
        case .regular:
            self.background(.ultraThinMaterial, in: shape)
        case .prominent:
            self.background(.thinMaterial, in: shape)
        case .clear:
            self.background(.ultraThinMaterial.opacity(0.65), in: shape)
        }
    }
}

/// A container that groups child views within a unified system Liquid Glass surface.
public struct GlassEffectContainer<Content: View>: View {
    private let content: Content
    private let style: GlassEffectStyle
    private let cornerRadius: CGFloat

    public init(
        style: GlassEffectStyle = .regular,
        cornerRadius: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .glassEffect(style, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Interactive button style with a native Liquid Glass backdrop.
public struct GlassButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Prominent button style with a vibrant tinted Liquid Glass surface.
public struct GlassProminentButtonStyle: ButtonStyle {
    private let tintColor: Color

    public init(tintColor: Color = .blue) {
        self.tintColor = tintColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(tintColor.opacity(0.85))
                }
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == GlassButtonStyle {
    /// Native system Liquid Glass button style.
    static var glass: GlassButtonStyle { GlassButtonStyle() }
}

public extension ButtonStyle where Self == GlassProminentButtonStyle {
    /// Native prominent Liquid Glass button style.
    static var glassProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() }

    /// Native prominent Liquid Glass button style with custom tint.
    static func glassProminent(tint: Color) -> GlassProminentButtonStyle {
        GlassProminentButtonStyle(tintColor: tint)
    }
}
