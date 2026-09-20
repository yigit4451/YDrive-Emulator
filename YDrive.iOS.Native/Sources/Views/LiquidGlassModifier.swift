import SwiftUI
import UIKit

// A bulletproof bridge to Apple's native CoreAnimation blur engine.
// This guarantees it composites correctly over CAMetalLayer.
struct NativeGlassView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        return view
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

extension View {
    // We use .systemThinMaterialLight to force a bright, icy glass look
    // that contrasts beautifully against both the game and black letterboxing.
    
    @ViewBuilder
    func applyLiquidGlass(cornerRadius: CGFloat = 16) -> some View {
        self.background(
            NativeGlassView(style: .systemThinMaterialLight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.4), lineWidth: 0.5) // Apple's signature 0.5pt rim light
        )
    }
    
    @ViewBuilder
    func applyLiquidGlassCapsule() -> some View {
        self.background(
            NativeGlassView(style: .systemThinMaterialLight)
                .clipShape(Capsule())
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
        )
    }
    
    @ViewBuilder
    func applyLiquidGlassCircle() -> some View {
        self.background(
            NativeGlassView(style: .systemThinMaterialLight)
                .clipShape(Circle())
        )
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
        )
    }
}
