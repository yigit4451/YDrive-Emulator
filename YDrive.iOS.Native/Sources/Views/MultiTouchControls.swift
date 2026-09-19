import SwiftUI
import UIKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - MultiTouch Button
// ─────────────────────────────────────────────────────────────────────────────

struct MultiTouchButton: UIViewRepresentable {
    var onStateChange: (Bool) -> Void

    func makeUIView(context: Context) -> TouchButtonView {
        let view = TouchButtonView()
        view.onStateChange = onStateChange
        return view
    }

    func updateUIView(_ uiView: TouchButtonView, context: Context) {
        uiView.onStateChange = onStateChange
    }

    class TouchButtonView: UIView {
        var onStateChange: ((Bool) -> Void)?
        private var isPressed = false

        init() {
            super.init(frame: .zero)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
            isUserInteractionEnabled = true
        }

        required init?(coder: NSCoder) { fatalError() }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            updateState(with: event)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            updateState(with: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            updateState(with: event)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            updateState(with: event)
        }

        private func updateState(with event: UIEvent?) {
            guard let touches = event?.touches(for: self) else { return }
            
            // Check if any touch is currently inside the bounds
            let isInside = touches.contains { touch in
                let phase = touch.phase
                guard phase == .began || phase == .moved || phase == .stationary else { return false }
                
                // Allow a slightly larger hit area (e.g. +20 points) for sliding
                let hitRect = bounds.insetBy(dx: -20, dy: -20)
                return hitRect.contains(touch.location(in: self))
            }

            if isInside != isPressed {
                isPressed = isInside
                onStateChange?(isInside)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - MultiTouch D-Pad
// ─────────────────────────────────────────────────────────────────────────────

struct MultiTouchDPad: UIViewRepresentable {
    var onStateChange: (_ up: Bool, _ down: Bool, _ left: Bool, _ right: Bool) -> Void

    func makeUIView(context: Context) -> TouchDPadView {
        let view = TouchDPadView()
        view.onStateChange = onStateChange
        return view
    }

    func updateUIView(_ uiView: TouchDPadView, context: Context) {
        uiView.onStateChange = onStateChange
    }

    class TouchDPadView: UIView {
        var onStateChange: ((_ up: Bool, _ down: Bool, _ left: Bool, _ right: Bool) -> Void)?
        
        private var state = (up: false, down: false, left: false, right: false)

        init() {
            super.init(frame: .zero)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
            isUserInteractionEnabled = true
        }

        required init?(coder: NSCoder) { fatalError() }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            updateState(with: event)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            updateState(with: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            updateState(with: event)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            updateState(with: event)
        }

        private func updateState(with event: UIEvent?) {
            guard let touches = event?.touches(for: self) else { return }
            
            var newState = (up: false, down: false, left: false, right: false)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            // Determine deadzone and max distance based on view size (e.g., 160x160)
            let threshold: CGFloat = 20.0
            
            // Allow sliding in from outside up to a margin
            let hitRect = bounds.insetBy(dx: -40, dy: -40)

            for touch in touches {
                let phase = touch.phase
                if phase == .began || phase == .moved || phase == .stationary {
                    let loc = touch.location(in: self)
                    
                    if hitRect.contains(loc) {
                        let dx = loc.x - center.x
                        let dy = loc.y - center.y
                        
                        if dx < -threshold { newState.left = true }
                        if dx > threshold { newState.right = true }
                        if dy < -threshold { newState.up = true }
                        if dy > threshold { newState.down = true }
                    }
                }
            }

            if newState != state {
                state = newState
                onStateChange?(state.up, state.down, state.left, state.right)
            }
        }
    }
}
