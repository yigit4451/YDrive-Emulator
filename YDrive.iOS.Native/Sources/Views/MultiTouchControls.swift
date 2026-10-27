import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import ObjectiveC.runtime

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

    /// Generous hit test rectangle so slight thumb offsets and edge taps register immediately on touchDown.
    var hitRect: CGRect {
        rect.insetBy(dx: -14, dy: -14)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Direct Zero-Delay Multi-Touch Gesture Recognizer
// ─────────────────────────────────────────────────────────────────────────────

/// Attached directly to `SurfaceView` so that `touchesBegan` is delivered during
/// Phase A of `UIWindow.sendEvent(_:)` (the gesture recognizer pass) on the very
/// first millisecond of finger contact (`touchDown`), bypassing any `delaysTouchesBegan`
/// gate imposed on `UIResponder.touchesBegan` by system/container gesture recognizers.
private final class DirectGamepadTouchRecognizer: UIGestureRecognizer {
    weak var surfaceView: TouchControlSurface.SurfaceView?

    init(surfaceView: TouchControlSurface.SurfaceView) {
        self.surfaceView = surfaceView
        super.init(target: nil, action: nil)
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        cancelsTouchesInView = false
        requiresExclusiveTouchType = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // Immediately strip touch-begin delays from any other recognizer tracking this touch
        for touch in touches {
            for gr in touch.gestureRecognizers ?? [] where gr !== self {
                gr.delaysTouchesBegan = false
                gr.delaysTouchesEnded = false
                gr.cancelsTouchesInView = false
            }
            for gr in touch.window?.gestureRecognizers ?? [] where gr !== self {
                gr.delaysTouchesBegan = false
                gr.delaysTouchesEnded = false
                gr.cancelsTouchesInView = false
            }
        }
        if let sv = surfaceView {
            TouchControlSurface.SurfaceView.stripAncestorGestureDelays(from: sv)
        }
        // Synchronously forward touchDown to SurfaceView while remaining in .possible
        // so system gesture gate recognizers never block or fail multi-touch sequences.
        surfaceView?.handleTouchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        surfaceView?.handleTouchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        surfaceView?.handleTouchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        surfaceView?.handleTouchesCancelled(touches, with: event)
    }

    override func reset() {
        super.reset()
        surfaceView?.pruneStaleTouches()
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
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
    var hapticEnabled: Bool = true
    var onButton: (UInt32, Bool) -> Void

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.onButton = onButton
        view.hapticEnabled = hapticEnabled
        view.regions = regions
        return view
    }

    func updateUIView(_ uiView: SurfaceView, context: Context) {
        uiView.onButton = onButton
        uiView.hapticEnabled = hapticEnabled
        uiView.regions = regions
        uiView.ensureGestureRecognizersConfigured()
    }

    static func dismantleUIView(_ uiView: SurfaceView, coordinator: ()) {
        uiView.releaseAll()
    }

    final class SurfaceView: UIView, UIGestureRecognizerDelegate {
        // RetroPad IDs used for the D-pad
        private static let idUp:    UInt32 = 4
        private static let idDown:  UInt32 = 5
        private static let idLeft:  UInt32 = 6
        private static let idRight: UInt32 = 7

        /// Dead zone (in points) around the D-pad centre.
        private static let dpadThreshold: CGFloat = 20

        var onButton: ((UInt32, Bool) -> Void)?
        var hapticEnabled: Bool = true
        var regions: [TouchRegion] = [] {
            didSet {
                if oldValue != regions { recompute() }
            }
        }

        private static let activeSurfaces = NSHashTable<SurfaceView>.weakObjects()
        private static var swizzledApplication = false
        private static var swizzledWindowClasses = Set<ObjectIdentifier>()
        private static var swizzledVCClasses = Set<ObjectIdentifier>()

        static var hasActiveSurfaceInWindow: Bool {
            for surface in activeSurfaces.allObjects {
                if surface.window != nil && !surface.isHidden && surface.alpha > 0.01 {
                    return true
                }
            }
            return false
        }

        private var activeTouches = Set<UITouch>()
        private var pressed = Set<UInt32>()
        private var directTouchRecognizer: DirectGamepadTouchRecognizer!
        private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

        var hasActiveTouches: Bool {
            !activeTouches.isEmpty
        }

        /// Returns true if a modal sheet or alert is currently presented above this surface's view controller.
        private var isCoveredByPresentedModal: Bool {
            var responder: UIResponder? = self
            while let curr = responder {
                if let vc = curr as? UIViewController {
                    return vc.presentedViewController != nil
                }
                responder = curr.next
            }
            return false
        }

        init() {
            super.init(frame: .zero)
            isMultipleTouchEnabled = true
            isUserInteractionEnabled = true
            isExclusiveTouch = false
            backgroundColor = .clear

            Self.activeSurfaces.add(self)
            Self.swizzleApplicationIfNeeded()

            let recognizer = DirectGamepadTouchRecognizer(surfaceView: self)
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
            self.directTouchRecognizer = recognizer
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        // MARK: Hit testing

        func isPointInAnyRegion(_ point: CGPoint) -> Bool {
            for region in regions {
                if region.hitRect.contains(point) {
                    return true
                }
            }
            return false
        }

        private func touchLocationInSelf(_ touch: UITouch, fallbackWindow: UIWindow) -> CGPoint {
            if let touchWindow = touch.window {
                let ptInTouchWin = touch.location(in: touchWindow)
                let ptInFallbackWin = (touchWindow === fallbackWindow)
                    ? ptInTouchWin
                    : fallbackWindow.convert(ptInTouchWin, from: touchWindow)
                return convert(ptInFallbackWin, from: fallbackWindow)
            } else {
                let ptInWin = touch.location(in: fallbackWindow)
                return convert(ptInWin, from: fallbackWindow)
            }
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            if isPointInAnyRegion(point) {
                // Strip touch-begin delays on ancestor & window recognizers during hitTest,
                // BEFORE UIWindow attaches gesture recognizers to the incoming UITouch.
                Self.stripAncestorGestureDelays(from: self)
                if let window = self.window {
                    Self.stripGestureGateDelays(in: window)
                }
                return true
            }
            return false
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow our own immediate touch recognizer; block any parent/container pan or pop recognizer.
            return gestureRecognizer === directTouchRecognizer
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            for gr in touch.window?.gestureRecognizers ?? [] where gr !== directTouchRecognizer {
                gr.delaysTouchesBegan = false
                gr.delaysTouchesEnded = false
                gr.cancelsTouchesInView = false
            }
            Self.stripAncestorGestureDelays(from: self)
            return true
        }

        // MARK: Direct UIApplication/UIWindow.sendEvent interception & System Gesture Deferral

        static func stripAncestorGestureDelays(from startView: UIView) {
            var current: UIView? = startView
            while let view = current {
                for gr in view.gestureRecognizers ?? [] {
                    if !(gr is DirectGamepadTouchRecognizer) {
                        gr.delaysTouchesBegan = false
                        gr.delaysTouchesEnded = false
                        gr.cancelsTouchesInView = false
                        let clsName = NSStringFromClass(type(of: gr))
                        if clsName.contains("SystemGestureGate") || clsName.contains("DelayedTouch") {
                            gr.isEnabled = false
                        }
                    }
                }
                current = view.superview
            }
        }

        private static func stripGestureGateDelays(in window: UIWindow) {
            for gr in window.gestureRecognizers ?? [] {
                gr.delaysTouchesBegan = false
                gr.delaysTouchesEnded = false
                gr.cancelsTouchesInView = false
                let clsName = NSStringFromClass(type(of: gr))
                if clsName.contains("SystemGestureGate") || clsName.contains("DelayedTouch") {
                    gr.isEnabled = false
                }
            }
        }

        private static func interceptApplicationEvent(event: UIEvent) {
            guard event.type == .touches else { return }
            let surfaces = activeSurfaces.allObjects.filter {
                $0.window != nil && !$0.isHidden && $0.alpha > 0.01 && $0.isUserInteractionEnabled
            }
            guard !surfaces.isEmpty else { return }

            for surface in surfaces {
                guard let window = surface.window else { continue }
                stripGestureGateDelays(in: window)
                stripAncestorGestureDelays(from: surface)
                surface.processDirectWindowEvent(event, in: window)
            }
        }

        private static func interceptWindowEvent(window: UIWindow, event: UIEvent) {
            guard event.type == .touches else { return }
            let surfaces = activeSurfaces.allObjects.filter {
                $0.window === window && !$0.isHidden && $0.alpha > 0.01 && $0.isUserInteractionEnabled
            }
            guard !surfaces.isEmpty else { return }

            stripGestureGateDelays(in: window)

            for surface in surfaces {
                stripAncestorGestureDelays(from: surface)
                surface.processDirectWindowEvent(event, in: window)
            }
        }

        private func processDirectWindowEvent(_ event: UIEvent, in window: UIWindow) {
            if isCoveredByPresentedModal {
                if !activeTouches.isEmpty {
                    releaseAll()
                }
                return
            }
            guard let allTouches = event.allTouches, !allTouches.isEmpty else { return }
            var needsRecompute = false

            for touch in allTouches {
                for gr in touch.gestureRecognizers ?? [] where gr !== directTouchRecognizer {
                    gr.delaysTouchesBegan = false
                    gr.delaysTouchesEnded = false
                    gr.cancelsTouchesInView = false
                }

                switch touch.phase {
                case .began, .moved, .stationary:
                    if activeTouches.contains(touch) {
                        needsRecompute = true
                    } else {
                        let localPoint = touchLocationInSelf(touch, fallbackWindow: window)
                        if isPointInAnyRegion(localPoint) {
                            activeTouches.insert(touch)
                            needsRecompute = true
                        }
                    }
                case .ended, .cancelled:
                    if activeTouches.remove(touch) != nil {
                        needsRecompute = true
                    }
                @unknown default:
                    break
                }
            }

            if needsRecompute {
                recompute()
            }
        }

        private static func swizzleApplicationIfNeeded() {
            guard !swizzledApplication else { return }
            swizzledApplication = true

            let cls: AnyClass = UIApplication.self
            let sendEventSel = #selector(UIApplication.sendEvent(_:))
            guard let method = class_getInstanceMethod(cls, sendEventSel) else { return }
            typealias OrigFn = @convention(c) (UIApplication, Selector, UIEvent) -> Void
            let origImp = method_getImplementation(method)
            let origFn = unsafeBitCast(origImp, to: OrigFn.self)

            let block: @convention(block) (UIApplication, UIEvent) -> Void = { app, event in
                MainActor.assumeIsolated {
                    TouchControlSurface.SurfaceView.interceptApplicationEvent(event: event)
                }
                origFn(app, sendEventSel, event)
            }
            let newImp = imp_implementationWithBlock(block)
            if !class_addMethod(cls, sendEventSel, newImp, method_getTypeEncoding(method)) {
                method_setImplementation(method, newImp)
            }
        }

        private static func swizzleWindowClassIfNeeded(_ cls: AnyClass) {
            let id = ObjectIdentifier(cls)
            guard !swizzledWindowClasses.contains(id) else { return }
            swizzledWindowClasses.insert(id)

            let sendEventSel = #selector(UIWindow.sendEvent(_:))
            guard let method = class_getInstanceMethod(cls, sendEventSel) else { return }
            typealias OrigFn = @convention(c) (UIWindow, Selector, UIEvent) -> Void
            let origImp = method_getImplementation(method)
            let origFn = unsafeBitCast(origImp, to: OrigFn.self)

            let block: @convention(block) (UIWindow, UIEvent) -> Void = { window, event in
                MainActor.assumeIsolated {
                    TouchControlSurface.SurfaceView.interceptWindowEvent(window: window, event: event)
                }
                origFn(window, sendEventSel, event)
            }
            let newImp = imp_implementationWithBlock(block)
            if !class_addMethod(cls, sendEventSel, newImp, method_getTypeEncoding(method)) {
                method_setImplementation(method, newImp)
            }
        }

        private static func swizzleViewControllerClassIfNeeded(_ cls: AnyClass) {
            let id = ObjectIdentifier(cls)
            guard !swizzledVCClasses.contains(id) else { return }
            swizzledVCClasses.insert(id)

            let edgeSel = #selector(getter: UIViewController.preferredScreenEdgesDeferringSystemGestures)
            if let method = class_getInstanceMethod(cls, edgeSel) {
                typealias OrigFn = @convention(c) (AnyObject, Selector) -> UInt
                let origImp = method_getImplementation(method)
                let origFn = unsafeBitCast(origImp, to: OrigFn.self)
                let block: @convention(block) (AnyObject) -> UInt = { obj in
                    if MainActor.assumeIsolated({ TouchControlSurface.SurfaceView.hasActiveSurfaceInWindow }) {
                        return UIRectEdge.all.rawValue
                    }
                    return origFn(obj, edgeSel)
                }
                let newImp = imp_implementationWithBlock(block)
                if !class_addMethod(cls, edgeSel, newImp, method_getTypeEncoding(method)) {
                    method_setImplementation(method, newImp)
                }
            }

            let autoHideSel = #selector(getter: UIViewController.prefersHomeIndicatorAutoHidden)
            if let method = class_getInstanceMethod(cls, autoHideSel) {
                typealias OrigFn = @convention(c) (AnyObject, Selector) -> Bool
                let origImp = method_getImplementation(method)
                let origFn = unsafeBitCast(origImp, to: OrigFn.self)
                let block: @convention(block) (AnyObject) -> Bool = { obj in
                    if MainActor.assumeIsolated({ TouchControlSurface.SurfaceView.hasActiveSurfaceInWindow }) {
                        return false
                    }
                    return origFn(obj, autoHideSel)
                }
                let newImp = imp_implementationWithBlock(block)
                if !class_addMethod(cls, autoHideSel, newImp, method_getTypeEncoding(method)) {
                    method_setImplementation(method, newImp)
                }
            }

            let childSel = #selector(getter: UIViewController.childForScreenEdgesDeferringSystemGestures)
            if let method = class_getInstanceMethod(cls, childSel) {
                typealias OrigFn = @convention(c) (AnyObject, Selector) -> UIViewController?
                let origImp = method_getImplementation(method)
                let origFn = unsafeBitCast(origImp, to: OrigFn.self)
                let block: @convention(block) (AnyObject) -> UIViewController? = { obj in
                    if MainActor.assumeIsolated({ TouchControlSurface.SurfaceView.hasActiveSurfaceInWindow }) {
                        if let nav = obj as? UINavigationController {
                            return nav.topViewController
                        }
                    }
                    return origFn(obj, childSel)
                }
                let newImp = imp_implementationWithBlock(block)
                if !class_addMethod(cls, childSel, newImp, method_getTypeEncoding(method)) {
                    method_setImplementation(method, newImp)
                }
            }
        }

        // MARK: Touch events (both DirectGamepadTouchRecognizer and UIResponder forward here)

        func handleTouchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            // Never filter by `touch.phase == .began`: if any system or hosting gesture gate
            // delayed `touchesBegan` by 1 frame (8-16ms), `touch.phase` is `.stationary` or `.moved`
            // when `touchesBegan` arrives. Accepting all non-ended touches guarantees immediate
            // registration while holding the button down.
            for touch in touches where touch.phase != .ended && touch.phase != .cancelled {
                activeTouches.insert(touch)
            }
            recompute()
        }

        func handleTouchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                if touch.phase == .ended || touch.phase == .cancelled {
                    activeTouches.remove(touch)
                } else {
                    activeTouches.insert(touch)
                }
            }
            recompute()
        }

        func handleTouchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                activeTouches.remove(touch)
            }
            recompute()
        }

        func handleTouchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                // Only remove the touch if the system actually cancelled or ended the UITouch itself.
                // If a parent UIGestureRecognizer cancelled view touches while the finger is still
                // physically on the screen (.began / .moved / .stationary), keep the button held!
                if touch.phase == .cancelled || touch.phase == .ended || touch.window == nil {
                    activeTouches.remove(touch)
                }
            }
            recompute()
        }

        func pruneStaleTouches() {
            let before = activeTouches.count
            activeTouches = activeTouches.filter {
                $0.phase != .ended && $0.phase != .cancelled
            }
            if activeTouches.count != before {
                recompute()
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            handleTouchesBegan(touches, with: event)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            handleTouchesMoved(touches, with: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            handleTouchesEnded(touches, with: event)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            handleTouchesCancelled(touches, with: event)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                Self.activeSurfaces.remove(self)
                releaseAll()
            } else {
                hapticGenerator.prepare()
                ensureGestureRecognizersConfigured()
                DispatchQueue.main.async { [weak self] in
                    self?.ensureGestureRecognizersConfigured()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.ensureGestureRecognizersConfigured()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    self?.ensureGestureRecognizersConfigured()
                }
            }
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            ensureGestureRecognizersConfigured()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            ensureGestureRecognizersConfigured()
        }

        func ensureGestureRecognizersConfigured() {
            Self.swizzleApplicationIfNeeded()
            guard let window = self.window else { return }

            Self.activeSurfaces.add(self)
            Self.swizzleWindowClassIfNeeded(type(of: window))
            Self.stripGestureGateDelays(in: window)
            Self.stripAncestorGestureDelays(from: self)
            Self.disableTouchDelaysRecursively(in: window)

            if let rootVC = window.rootViewController {
                Self.configureViewControllerHierarchy(rootVC)
            }

            var responder: UIResponder? = self
            while let r = responder {
                if let vc = r as? UIViewController {
                    Self.swizzleViewControllerClassIfNeeded(type(of: vc))
                    vc.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
                    vc.setNeedsUpdateOfHomeIndicatorAutoHidden()

                    for gr in vc.view.gestureRecognizers ?? [] where !(gr is DirectGamepadTouchRecognizer) {
                        gr.delaysTouchesBegan = false
                        gr.delaysTouchesEnded = false
                        gr.cancelsTouchesInView = false
                    }
                    if let pop = vc.navigationController?.interactivePopGestureRecognizer {
                        pop.delaysTouchesBegan = false
                        pop.delaysTouchesEnded = false
                        pop.isEnabled = false
                    }
                    if #available(iOS 18.0, *),
                       let contentPop = vc.navigationController?.interactiveContentPopGestureRecognizer {
                        contentPop.delaysTouchesBegan = false
                        contentPop.delaysTouchesEnded = false
                        contentPop.isEnabled = false
                    }
                    if let presented = vc.presentationController?.presentedView {
                        Self.disableTouchDelaysRecursively(in: presented)
                    }
                    if let container = vc.presentationController?.containerView {
                        Self.disableTouchDelaysRecursively(in: container)
                    }
                }
                if let nav = r as? UINavigationController {
                    Self.swizzleViewControllerClassIfNeeded(type(of: nav))
                    nav.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
                    nav.setNeedsUpdateOfHomeIndicatorAutoHidden()
                    nav.interactivePopGestureRecognizer?.delaysTouchesBegan = false
                    nav.interactivePopGestureRecognizer?.delaysTouchesEnded = false
                    nav.interactivePopGestureRecognizer?.isEnabled = false
                    if #available(iOS 18.0, *) {
                        nav.interactiveContentPopGestureRecognizer?.delaysTouchesBegan = false
                        nav.interactiveContentPopGestureRecognizer?.delaysTouchesEnded = false
                        nav.interactiveContentPopGestureRecognizer?.isEnabled = false
                    }
                }
                responder = r.next
            }
        }

        private static func configureViewControllerHierarchy(_ vc: UIViewController) {
            swizzleViewControllerClassIfNeeded(type(of: vc))
            vc.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
            vc.setNeedsUpdateOfHomeIndicatorAutoHidden()
            for child in vc.children {
                configureViewControllerHierarchy(child)
            }
            if let presented = vc.presentedViewController {
                configureViewControllerHierarchy(presented)
            }
        }

        private static func disableTouchDelaysRecursively(in view: UIView) {
            for gr in view.gestureRecognizers ?? [] where !(gr is DirectGamepadTouchRecognizer) {
                gr.delaysTouchesBegan = false
                gr.delaysTouchesEnded = false
                gr.cancelsTouchesInView = false
                let clsName = NSStringFromClass(type(of: gr))
                if clsName.contains("SystemGestureGate") || clsName.contains("DelayedTouch") {
                    gr.isEnabled = false
                }
            }
            for sub in view.subviews {
                disableTouchDelaysRecursively(in: sub)
            }
        }

        /// Releases every button (used when the view goes away).
        func releaseAll() {
            activeTouches.removeAll()
            recompute()
        }

        // MARK: State computation

        private func recompute() {
            activeTouches = activeTouches.filter {
                $0.phase != .ended && $0.phase != .cancelled
            }

            var next = Set<UInt32>()

            for touch in activeTouches {
                let point = self.window.map { touchLocationInSelf(touch, fallbackWindow: $0) } ?? touch.location(in: self)

                // Buttons: prioritize direct hits inside `rect` over outer `hitRect` padding,
                // then pick the nearest button center.
                var bestID: UInt32?
                var bestIsInsidePrimaryRect = false
                var bestDistance = CGFloat.greatestFiniteMagnitude
                for region in regions {
                    guard case .button(let id) = region.kind, region.hitRect.contains(point) else { continue }
                    let insidePrimary = region.rect.contains(point)
                    let distance = hypot(point.x - region.rect.midX, point.y - region.rect.midY)
                    if insidePrimary && !bestIsInsidePrimaryRect {
                        bestIsInsidePrimaryRect = true
                        bestDistance = distance
                        bestID = id
                    } else if insidePrimary == bestIsInsidePrimaryRect && distance < bestDistance {
                        bestDistance = distance
                        bestID = id
                    }
                }

                // D-pad: evaluate if this touch did not match a button, or if it is closer to the D-pad center.
                var matchedDpad = false
                for region in regions where region.kind == .dpad && region.hitRect.contains(point) {
                    let dpadDistance = hypot(point.x - region.rect.midX, point.y - region.rect.midY)
                    if bestID == nil || (!bestIsInsidePrimaryRect && dpadDistance < bestDistance) {
                        matchedDpad = true
                        let dx = point.x - region.rect.midX
                        let dy = point.y - region.rect.midY
                        if dx < -Self.dpadThreshold { next.insert(Self.idLeft) }
                        if dx >  Self.dpadThreshold { next.insert(Self.idRight) }
                        if dy < -Self.dpadThreshold { next.insert(Self.idUp) }
                        if dy >  Self.dpadThreshold { next.insert(Self.idDown) }
                    }
                }

                if !matchedDpad, let bestID {
                    next.insert(bestID)
                }
            }

            guard next != pressed else { return }

            let released = pressed.subtracting(next)
            let newlyPressed = next.subtracting(pressed)
            pressed = next

            for id in released.sorted() { onButton?(id, false) }
            for id in newlyPressed.sorted() { onButton?(id, true) }

            if !newlyPressed.isEmpty && hapticEnabled {
                hapticGenerator.impactOccurred()
                hapticGenerator.prepare()
            }
        }
    }
}
