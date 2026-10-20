import SwiftUI
import UIKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Touch regions
// ─────────────────────────────────────────────────────────────────────────────

/// One touch-sensitive area of the on-screen gamepad, expressed in the
/// coordinate space of `TouchControlSurface`.
struct TouchRegion: Equatable {
    enum Kind: Equatable {
        /// A single RetroPad button.
        case button(UInt32)
        /// The directional pad (maps to UP / DOWN / LEFT / RIGHT).
        case dpad
    }

    let kind: Kind
    let rect: CGRect
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Touch control surface
// ─────────────────────────────────────────────────────────────────────────────

/// A single full-screen, multi-touch UIKit view that drives the whole on-screen
/// gamepad.
///
/// All finger positions are evaluated against the supplied `regions` on every
/// touch event. The set of pressed RetroPad buttons is recomputed from scratch
/// and only the differences are reported through `onButton`. Because this is
/// one view that owns every touch, input does not depend on per-button SwiftUI
/// hit-testing or layout timing, and it cannot get stuck when a touch is
/// cancelled or the view disappears.
struct TouchControlSurface: UIViewRepresentable {
    var regions: [TouchRegion]
    var onButton: (UInt32, Bool) -> Void

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.onButton = onButton
        view.regions = regions
        return view
    }

    func updateUIView(_ uiView: SurfaceView, context: Context) {
        uiView.onButton = onButton
        uiView.regions = regions
    }

    static func dismantleUIView(_ uiView: SurfaceView, coordinator: ()) {
        uiView.releaseAll()
    }

    final class SurfaceView: UIView {
        // RetroPad IDs used for the D-pad
        private static let idUp:    UInt32 = 4
        private static let idDown:  UInt32 = 5
        private static let idLeft:  UInt32 = 6
        private static let idRight: UInt32 = 7

        /// Dead zone (in points) around the D-pad centre.
        private static let dpadThreshold: CGFloat = 20

        var onButton: ((UInt32, Bool) -> Void)?
        var regions: [TouchRegion] = [] {
            didSet {
                if oldValue != regions { recompute() }
            }
        }

        private var activeTouches = Set<UITouch>()
        private var pressed = Set<UInt32>()

        init() {
            super.init(frame: .zero)
            isMultipleTouchEnabled = true
            isUserInteractionEnabled = true
            isExclusiveTouch = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        // MARK: Hit testing

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            for region in regions {
                if region.rect.contains(point) {
                    return true
                }
            }
            return false
        }

        // MARK: Touch events

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            activeTouches.formUnion(touches)
            recompute()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            recompute()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            activeTouches.subtract(touches)
            recompute()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            activeTouches.subtract(touches)
            recompute()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { releaseAll() }
        }

        /// Releases every button (used when the view goes away).
        func releaseAll() {
            activeTouches.removeAll()
            recompute()
        }

        // MARK: State computation

        private func recompute() {
            var next = Set<UInt32>()

            for touch in activeTouches {
                let point = touch.location(in: self)

                // D-pad: a touch inside the pad is translated into directions.
                for region in regions where region.kind == .dpad && region.rect.contains(point) {
                    let dx = point.x - region.rect.midX
                    let dy = point.y - region.rect.midY
                    if dx < -Self.dpadThreshold { next.insert(Self.idLeft) }
                    if dx >  Self.dpadThreshold { next.insert(Self.idRight) }
                    if dy < -Self.dpadThreshold { next.insert(Self.idUp) }
                    if dy >  Self.dpadThreshold { next.insert(Self.idDown) }
                }

                // Buttons: when padded hit areas overlap, the nearest button wins.
                var bestID: UInt32?
                var bestDistance = CGFloat.greatestFiniteMagnitude
                for region in regions {
                    guard case .button(let id) = region.kind, region.rect.contains(point) else { continue }
                    let distance = hypot(point.x - region.rect.midX, point.y - region.rect.midY)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestID = id
                    }
                }
                if let bestID { next.insert(bestID) }
            }

            guard next != pressed else { return }

            let released = pressed.subtracting(next)
            let newlyPressed = next.subtracting(pressed)
            pressed = next

            for id in released.sorted() { onButton?(id, false) }
            for id in newlyPressed.sorted() { onButton?(id, true) }
        }
    }
}
