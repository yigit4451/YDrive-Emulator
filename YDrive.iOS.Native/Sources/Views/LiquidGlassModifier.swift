import SwiftUI

extension View {
    @ViewBuilder
    func applyLiquidGlass(cornerRadius: CGFloat = 16) -> some View {
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    
    @ViewBuilder
    func applyLiquidGlassCapsule() -> some View {
        self.background(.ultraThinMaterial, in: Capsule())
    }
    
    @ViewBuilder
    func applyLiquidGlassCircle() -> some View {
        self.background(.ultraThinMaterial, in: Circle())
    }
}
