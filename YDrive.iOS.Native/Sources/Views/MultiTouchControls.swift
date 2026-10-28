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
// MARK: - Emulator UIViewController with System Screen Edge Gesture Deferral
// ─────────────────────────────────────────────────────────────────────────────

/// Native UIViewController subclass for the Emulator screen that explicitly
/// overrides `preferredScreenEdgesDeferringSystemGestures` to `.all` so iOS
/// never delays first-finger touches near the bottom/right screen edges.
final class EmulatorEdgeDeferringViewController: UIViewController {
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        return .all
    }

    override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
        return nil
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return false
    }

    override var childForHomeIndicatorAutoHidden: UIViewController? {
        return nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        propagateDeferralUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        propagateDeferralUpdate()
    }

    func propagateDeferralUpdate() {
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        setNeedsUpdateOfHomeIndicatorAutoHidden()

        var current: UIViewController? = parent
        while let vc = current {
            TouchControlSurface.SurfaceView.ensureViewControllerDefersEdgeGestures(vc)
            vc.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
            vc.setNeedsUpdateOfHomeIndicatorAutoHidden()
            current = vc.parent ?? vc.presentingViewController
        }

        if let window = view.window {
            if let root = window.rootViewController {
                TouchControlSurface.SurfaceView.ensureViewControllerDefersEdgeGestures(root)
                root.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
                root.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
            if let presented = window.rootViewController?.presentedViewController {
                TouchControlSurface.SurfaceView.ensureViewControllerDefersEdgeGestures(presented)
                presented.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
                presented.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Immediate Touch Shield Gesture Recognizer
// ─────────────────────────────────────────────────────────────────────────────

/// Prevents any ancestor SwiftUI / UINavigationController / UIPresentationController
/// gesture recognizer from holding single-finger touches in `.possible` state until release,
/// and forwards `touchesBegan` / `touchesMoved` / `touchesEnded` / `touchesCancelled`
/// to `SurfaceView` on the exact millisecond of finger contact.
private final class ImmediateTouchShieldRecognizer: UIGestureRecognizer {
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
        if state == .possible {
            state = .began
        } else {
            state = .changed
        }
        surfaceView?.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .began || state == .changed {
            state = .changed
        }
        surfaceView?.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        surfaceView?.touchesEnded(touches, with: event)
        if let sv = surfaceView, !sv.hasActiveTouches {
            state = .ended
        } else {
            state = .changed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        surfaceView?.touchesCancelled(touches, with: event)
        if let sv = surfaceView, !sv.hasActiveTouches {
            state = .cancelled
        } else {
            state = .changed
        }
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Prevent ancestor container/navigation gesture recognizers from swallowing or delaying gamepad touches.
        return preventedGestureRecognizer !== self
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return otherGestureRecognizer !== self
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Touch control surface (Pure UIKit touchesBegan / touchesEnded)
// ─────────────────────────────────────────────────────────────────────────────

/// A single full-screen, multi-touch UIKit view that drives the whole on-screen
/// gamepad using `touchesBegan` / `touchesMoved` / `touchesEnded` / `touchesCancelled`.
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
        uiView.configureSystemGestureDeferralAndTouchDelays()
    }

    static func dismantleUIView(_ uiView: SurfaceView, coordinator: ()) {
        uiView.releaseAll()
    }

    final class SurfaceView: UIView, UIGestureRecognizerDelegate {
        // RetroPad IDs
        private static let idB:     UInt32 = 0
        private static let idY:     UInt32 = 1
        private static let idUp:    UInt32 = 4
        private static let idDown:  UInt32 = 5
        private static let idLeft:  UInt32 = 6
        private static let idRight: UInt32 = 7
        private static let idA:     UInt32 = 8

        /// Dead zone (in points) around the D-pad centre.
        private static let dpadThreshold: CGFloat = 20

        var onButton: ((UInt32, Bool) -> Void)?
        var hapticEnabled: Bool = true
        var regions: [TouchRegion] = []

        private static let activeSurfaces = NSHashTable<SurfaceView>.weakObjects()
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
        private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
        private let edgeDeferralVC = EmulatorEdgeDeferringViewController()
        private var shieldRecognizer: ImmediateTouchShieldRecognizer!

        var hasActiveTouches: Bool {
            !activeTouches.isEmpty
        }

        init() {
            super.init(frame: .zero)
            isMultipleTouchEnabled = true
            isUserInteractionEnabled = true
            isExclusiveTouch = false
            backgroundColor = .clear

            Self.activeSurfaces.add(self)

            edgeDeferralVC.view.frame = .zero
            edgeDeferralVC.view.isHidden = true
            edgeDeferralVC.view.isUserInteractionEnabled = false
            addSubview(edgeDeferralVC.view)

            let shield = ImmediateTouchShieldRecognizer(surfaceView: self)
            shield.delegate = self
            addGestureRecognizer(shield)
            self.shieldRecognizer = shield
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

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            if isPointInAnyRegion(point) {
                Self.disableAncestorTouchDelays(from: self)
                if let window = self.window {
                    Self.disableWindowTouchDelays(in: window)
                }
                return true
            }
            return false
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            return gestureRecognizer === shieldRecognizer
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return otherGestureRecognizer !== shieldRecognizer
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return false
        }

        // MARK: Direct UIKit touchesBegan / touchesMoved / touchesEnded / touchesCancelled

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            var newlyMatched = Set<UInt32>()
            // TEMP diagnostics: how long iOS took to deliver the oldest touch to us.
            var deliveryMs = 0.0

            for touch in touches {
                deliveryMs = max(deliveryMs, InputLatencyProbe.nowMs - touch.timestamp * 1000)
                for gr in touch.gestureRecognizers ?? [] where gr !== shieldRecognizer {
                    gr.delaysTouchesBegan = false
                    gr.delaysTouchesEnded = false
                    gr.cancelsTouchesInView = false
                }
                activeTouches.insert(touch)

                let point = touch.location(in: self)
                let matchedIDs = buttonsAtPoint(point)
                for id in matchedIDs {
                    newlyMatched.insert(id)
                }
            }

            // Immediately press any button entered in touchesBegan
            var triggeredHaptic = false
            for id in newlyMatched.sorted() {
                if !pressed.contains(id) {
                    pressed.insert(id)
                    if id == Self.idY || id == Self.idA {
                        print("DEBUG: A pressed = true")
                    } else if id == Self.idB {
                        print("DEBUG: B pressed = true")
                    }
                    onButton?(id, true)
                    InputLatencyProbe.log(String(
                        format: "down   id=%u hw→app=%.2fms fingersOnScreen=%d",
                        id, deliveryMs, activeTouches.count))
                    triggeredHaptic = true
                }
            }

            if triggeredHaptic && hapticEnabled {
                hapticGenerator.impactOccurred()
                hapticGenerator.prepare()
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                if touch.phase == .ended || touch.phase == .cancelled {
                    activeTouches.remove(touch)
                } else {
                    activeTouches.insert(touch)
                }
            }
            recomputeForActiveTouches()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                activeTouches.remove(touch)
            }
            // touchesEnded ONLY releases buttons (pressed = false); it NEVER sets pressed = true.
            releaseButtonsNoLongerHeld()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                activeTouches.remove(touch)
            }
            // touchesCancelled ONLY releases buttons (pressed = false); it NEVER sets pressed = true.
            releaseButtonsNoLongerHeld()
        }

        /// Evaluates which RetroPad button IDs (or D-Pad directions) contain `point`.
        private func buttonsAtPoint(_ point: CGPoint) -> Set<UInt32> {
            var result = Set<UInt32>()

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

            var matchedDpad = false
            for region in regions where region.kind == .dpad && region.hitRect.contains(point) {
                let dpadDistance = hypot(point.x - region.rect.midX, point.y - region.rect.midY)
                if bestID == nil || (!bestIsInsidePrimaryRect && dpadDistance < bestDistance) {
                    matchedDpad = true
                    let dx = point.x - region.rect.midX
                    let dy = point.y - region.rect.midY
                    if dx < -Self.dpadThreshold { result.insert(Self.idLeft) }
                    if dx >  Self.dpadThreshold { result.insert(Self.idRight) }
                    if dy < -Self.dpadThreshold { result.insert(Self.idUp) }
                    if dy >  Self.dpadThreshold { result.insert(Self.idDown) }
                }
            }

            if !matchedDpad, let bestID {
                result.insert(bestID)
            }

            return result
        }

        /// Used ONLY by `touchesEnded` and `touchesCancelled`: strictly sends `pressed = false`
        /// for buttons no longer held, and NEVER sends `pressed = true`.
        private func releaseButtonsNoLongerHeld() {
            activeTouches = activeTouches.filter {
                $0.phase != .ended && $0.phase != .cancelled
            }

            var stillHeld = Set<UInt32>()
            for touch in activeTouches {
                let point = touch.location(in: self)
                stillHeld.formUnion(buttonsAtPoint(point))
            }

            let released = pressed.subtracting(stillHeld)
            guard !released.isEmpty else { return }

            pressed.subtract(released)
            for id in released.sorted() {
                if id == Self.idY || id == Self.idA {
                    print("DEBUG: A pressed = false")
                } else if id == Self.idB {
                    print("DEBUG: B pressed = false")
                }
                onButton?(id, false)
                InputLatencyProbe.log(String(format: "up     id=%u", id))
            }
        }

        /// Used during `touchesMoved` (e.g. sliding thumb across D-Pad directions).
        private func recomputeForActiveTouches() {
            activeTouches = activeTouches.filter {
                $0.phase != .ended && $0.phase != .cancelled
            }

            var next = Set<UInt32>()
            for touch in activeTouches {
                let point = touch.location(in: self)
                next.formUnion(buttonsAtPoint(point))
            }

            guard next != pressed else { return }

            let released = pressed.subtracting(next)
            let newlyPressed = next.subtracting(pressed)
            pressed = next

            for id in released.sorted() {
                onButton?(id, false)
                InputLatencyProbe.log(String(format: "slide-up id=%u", id))
            }
            for id in newlyPressed.sorted() {
                onButton?(id, true)
                InputLatencyProbe.log(String(format: "slide-down id=%u (via touchesMoved)", id))
            }

            if !newlyPressed.isEmpty && hapticEnabled {
                hapticGenerator.impactOccurred()
                hapticGenerator.prepare()
            }
        }

        /// Releases every button (used when the view goes away).
        func releaseAll() {
            activeTouches.removeAll()
            releaseButtonsNoLongerHeld()
        }

        // MARK: View Lifecycle & System Gesture Deferral

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                Self.activeSurfaces.remove(self)
                releaseAll()
            } else {
                Self.activeSurfaces.add(self)
                hapticGenerator.prepare()
                configureSystemGestureDeferralAndTouchDelays()
                DispatchQueue.main.async { [weak self] in
                    self?.configureSystemGestureDeferralAndTouchDelays()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.configureSystemGestureDeferralAndTouchDelays()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.configureSystemGestureDeferralAndTouchDelays()
                }
            }
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            configureSystemGestureDeferralAndTouchDelays()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            configureSystemGestureDeferralAndTouchDelays()
        }

        func configureSystemGestureDeferralAndTouchDelays() {
            guard let window = self.window else { return }

            Self.activeSurfaces.add(self)
            Self.ensureClassDefersEdgeGestures(UIViewController.self)
            Self.disableWindowTouchDelays(in: window)
            Self.disableAncestorTouchDelays(from: self)

            if let rootVC = window.rootViewController {
                Self.configureViewControllerHierarchy(rootVC)
            }

            var responder: UIResponder? = self
            while let r = responder {
                if let vc = r as? UIViewController {
                    if edgeDeferralVC.parent == nil && !(vc is UINavigationController) {
                        vc.addChild(edgeDeferralVC)
                        edgeDeferralVC.didMove(toParent: vc)
                    }
                    Self.ensureViewControllerDefersEdgeGestures(vc)
                    vc.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
                    vc.setNeedsUpdateOfHomeIndicatorAutoHidden()

                    if let nav = vc.navigationController {
                        Self.ensureViewControllerDefersEdgeGestures(nav)
                        nav.interactivePopGestureRecognizer?.delaysTouchesBegan = false
                        nav.interactivePopGestureRecognizer?.delaysTouchesEnded = false
                        nav.interactivePopGestureRecognizer?.isEnabled = false
                        if #available(iOS 18.0, *) {
                            nav.interactiveContentPopGestureRecognizer?.delaysTouchesBegan = false
                            nav.interactiveContentPopGestureRecognizer?.delaysTouchesEnded = false
                            nav.interactiveContentPopGestureRecognizer?.isEnabled = false
                        }
                        nav.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
                        nav.setNeedsUpdateOfHomeIndicatorAutoHidden()
                    }
                }
                responder = r.next
            }

            edgeDeferralVC.propagateDeferralUpdate()
        }

        private static func configureViewControllerHierarchy(_ vc: UIViewController) {
            ensureViewControllerDefersEdgeGestures(vc)
            vc.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
            vc.setNeedsUpdateOfHomeIndicatorAutoHidden()
            for child in vc.children {
                configureViewControllerHierarchy(child)
            }
            if let presented = vc.presentedViewController {
                configureViewControllerHierarchy(presented)
            }
        }

        static func ensureViewControllerDefersEdgeGestures(_ vc: UIViewController) {
            var classes: [AnyClass] = []
            var curr: AnyClass? = type(of: vc)
            while let c = curr, c != UIResponder.self && c != NSObject.self {
                classes.append(c)
                curr = class_getSuperclass(c)
            }
            for cls in classes.reversed() {
                ensureClassDefersEdgeGestures(cls)
            }
        }

        private static func ensureClassDefersEdgeGestures(_ cls: AnyClass) {
            let id = ObjectIdentifier(cls)
            guard !swizzledVCClasses.contains(id) else { return }
            swizzledVCClasses.insert(id)

            let superCls: AnyClass? = (cls == UIViewController.self) ? nil : class_getSuperclass(cls)

            // 1. preferredScreenEdgesDeferringSystemGestures -> .all
            let edgeSel = #selector(getter: UIViewController.preferredScreenEdgesDeferringSystemGestures)
            if let method = class_getInstanceMethod(cls, edgeSel) {
                let superMethod = superCls.flatMap { class_getInstanceMethod($0, edgeSel) }
                if cls == UIViewController.self || method != superMethod {
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
            }

            // 2. childForScreenEdgesDeferringSystemGestures -> nil
            let childSel = #selector(getter: UIViewController.childForScreenEdgesDeferringSystemGestures)
            if let method = class_getInstanceMethod(cls, childSel) {
                let superMethod = superCls.flatMap { class_getInstanceMethod($0, childSel) }
                if cls == UIViewController.self || method != superMethod {
                    typealias OrigFn = @convention(c) (AnyObject, Selector) -> UIViewController?
                    let origImp = method_getImplementation(method)
                    let origFn = unsafeBitCast(origImp, to: OrigFn.self)
                    let block: @convention(block) (AnyObject) -> UIViewController? = { obj in
                        if MainActor.assumeIsolated({ TouchControlSurface.SurfaceView.hasActiveSurfaceInWindow }) {
                            return nil
                        }
                        return origFn(obj, childSel)
                    }
                    let newImp = imp_implementationWithBlock(block)
                    if !class_addMethod(cls, childSel, newImp, method_getTypeEncoding(method)) {
                        method_setImplementation(method, newImp)
                    }
                }
            }

            // 3. prefersHomeIndicatorAutoHidden -> false
            let autoHideSel = #selector(getter: UIViewController.prefersHomeIndicatorAutoHidden)
            if let method = class_getInstanceMethod(cls, autoHideSel) {
                let superMethod = superCls.flatMap { class_getInstanceMethod($0, autoHideSel) }
                if cls == UIViewController.self || method != superMethod {
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
            }

            // 4. childForHomeIndicatorAutoHidden -> nil
            let childAutoHideSel = #selector(getter: UIViewController.childForHomeIndicatorAutoHidden)
            if let method = class_getInstanceMethod(cls, childAutoHideSel) {
                let superMethod = superCls.flatMap { class_getInstanceMethod($0, childAutoHideSel) }
                if cls == UIViewController.self || method != superMethod {
                    typealias OrigFn = @convention(c) (AnyObject, Selector) -> UIViewController?
                    let origImp = method_getImplementation(method)
                    let origFn = unsafeBitCast(origImp, to: OrigFn.self)
                    let block: @convention(block) (AnyObject) -> UIViewController? = { obj in
                        if MainActor.assumeIsolated({ TouchControlSurface.SurfaceView.hasActiveSurfaceInWindow }) {
                            return nil
                        }
                        return origFn(obj, childAutoHideSel)
                    }
                    let newImp = imp_implementationWithBlock(block)
                    if !class_addMethod(cls, childAutoHideSel, newImp, method_getTypeEncoding(method)) {
                        method_setImplementation(method, newImp)
                    }
                }
            }
        }

        private static func disableAncestorTouchDelays(from startView: UIView) {
            var current: UIView? = startView
            while let view = current {
                for gr in view.gestureRecognizers ?? [] where !(gr is ImmediateTouchShieldRecognizer) {
                    gr.delaysTouchesBegan = false
                    gr.delaysTouchesEnded = false
                    gr.cancelsTouchesInView = false
                }
                current = view.superview
            }
        }

        private static func disableWindowTouchDelays(in window: UIWindow) {
            for gr in window.gestureRecognizers ?? [] where !(gr is ImmediateTouchShieldRecognizer) {
                gr.delaysTouchesBegan = false
                gr.delaysTouchesEnded = false
                gr.cancelsTouchesInView = false
            }
        }
    }
}
