import SwiftUI

extension View {
    /// Applies a true native iOS Material background with a subtle edge light stroke
    /// to mimic the depth of Liquid Glass, using safe and valid Xcode 16.2 APIs.
    @ViewBuilder
    func applyLiquidGlass<S: InsettableShape>(shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.1), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }

    /// Convenience for RoundedRectangle Liquid Glass
    @ViewBuilder
    func applyLiquidGlass(cornerRadius: CGFloat = 16) -> some View {
        self.applyLiquidGlass(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    
    /// Convenience for Capsule Liquid Glass
    @ViewBuilder
    func applyLiquidGlassCapsule() -> some View {
        self.applyLiquidGlass(shape: Capsule())
    }
    
    /// Convenience for Circle Liquid Glass
    @ViewBuilder
    func applyLiquidGlassCircle() -> some View {
        self.applyLiquidGlass(shape: Circle())
    }
}
