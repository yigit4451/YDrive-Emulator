import SwiftUI

extension View {
    @ViewBuilder
    func applyLiquidGlass(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 18.0, *) { // Targetting iOS 18+ to be safe
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
    
    @ViewBuilder
    func applyLiquidGlassCapsule() -> some View {
        if #available(iOS 18.0, *) {
            self.background(.ultraThinMaterial, in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }
    
    @ViewBuilder
    func applyLiquidGlassCircle() -> some View {
        if #available(iOS 18.0, *) {
            self.background(.ultraThinMaterial, in: Circle())
        } else {
            self.background(.ultraThinMaterial, in: Circle())
        }
    }
}
