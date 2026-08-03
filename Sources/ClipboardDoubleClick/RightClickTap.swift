import AppKit
import Cocoa

/// Détecte un DOUBLE clic droit global (n'importe quelle app) et avale
/// uniquement le 2e clic de la paire — le 1er clic droit passe toujours
/// normalement (menu contextuel habituel préservé).
///
/// Nécessite la permission Accessibilité (System Settings > Confidentialité
/// et sécurité > Accessibilité).
final class RightClickTap {

    /// Renvoie true si le geste doit être ignoré pour l'app actuellement au premier plan.
    var isCurrentAppExcluded: (() -> Bool) = { false }
    /// Appelé quand un vrai double clic droit est détecté, avec la position écran du clic.
    var onDoubleRightClick: ((CGPoint) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var lastRightDownTime: CFTimeInterval = 0
    private var lastRightDownLocation: CGPoint = .zero

    private let distanceThreshold: CGFloat = 6.0

    static func requestAccessibilityPermissionIfNeeded() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        let mask: CGEventMask = (1 << CGEventType.rightMouseDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<RightClickTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(proxy: proxy, type: type, event: event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            print("[ClipboardDoubleClick] Impossible de créer le event tap — vérifie la permission Accessibilité.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS peut désactiver le tap (timeout, etc.) — on le réactive.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .rightMouseDown else {
            return Unmanaged.passUnretained(event)
        }

        let now = CACurrentMediaTime()
        let location = event.location
        let dt = now - lastRightDownTime
        let dx = location.x - lastRightDownLocation.x
        let dy = location.y - lastRightDownLocation.y
        let distance = (dx * dx + dy * dy).squareRoot()

        let isDoubleClick = dt < NSEvent.doubleClickInterval && distance < distanceThreshold

        if isDoubleClick {
            // On consomme cette paire pour éviter qu'un triple clic ne soit
            // interprété comme un 2e double clic immédiat.
            lastRightDownTime = 0
            lastRightDownLocation = .zero

            if isCurrentAppExcluded() {
                return Unmanaged.passUnretained(event)
            }

            DispatchQueue.main.async { [weak self] in
                self?.onDoubleRightClick?(location)
            }
            // On avale le 2e clic : pas de menu contextuel système qui s'ouvre en plus.
            return nil
        } else {
            lastRightDownTime = now
            lastRightDownLocation = location
            // 1er clic droit : comportement normal préservé (menu contextuel de l'app).
            return Unmanaged.passUnretained(event)
        }
    }
}
