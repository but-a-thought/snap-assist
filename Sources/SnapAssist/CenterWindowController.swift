import AppKit

/// Conta le pressioni consecutive di Control, ignorando quelle usate come
/// modificatore (Ctrl+C, Ctrl+clic, Ctrl+Shift…).
struct ControlTapSequence {
    var tapsRequired = 2
    var maximumInterval: TimeInterval = 0.4

    private(set) var count = 0
    private var lastTapAt: Date?

    mutating func registerTap(at date: Date) -> Bool {
        if let lastTapAt, date.timeIntervalSince(lastTapAt) <= maximumInterval {
            count += 1
        } else {
            count = 1
        }
        lastTapAt = date

        if count >= max(2, tapsRequired) {
            reset()
            return true
        }
        return false
    }

    mutating func reset() {
        count = 0
        lastTapAt = nil
    }
}

enum Centering {
    /// Mantiene la dimensione della finestra, la riduce solo se non entra
    /// nello schermo e la centra nel visibleFrame.
    static func frame(for window: NSRect, in screen: NSRect) -> NSRect {
        let width = min(window.width, screen.width)
        let height = min(window.height, screen.height)
        return NSRect(
            x: screen.midX - width / 2,
            y: screen.midY - height / 2,
            width: width,
            height: height
        ).integral
    }
}

/// Doppio (o triplo) Control per centrare la finestra in primo piano.
final class CenterWindowController {
    var isEnabled = false
    var tapsRequired = 2
    var onCentered: ((pid_t, AXUIElement) -> Void)?

    private var monitor: Any?
    private var sequence = ControlTapSequence()
    private var controlDown = false
    private var usedAsModifier = false

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [
            .flagsChanged,
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel
        ]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        sequence.reset()
        controlDown = false
        usedAsModifier = false
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let control = event.modifierFlags.contains(.control)
            let otherModifiers = event.modifierFlags.intersection([.shift, .option, .command])

            if control != controlDown {
                controlDown = control
                if control {
                    usedAsModifier = !otherModifiers.isEmpty
                } else {
                    if !usedAsModifier, otherModifiers.isEmpty {
                        sequence.tapsRequired = tapsRequired
                        if sequence.registerTap(at: Date()) {
                            centerFrontWindow()
                        }
                    }
                }
            } else if controlDown, !otherModifiers.isEmpty {
                usedAsModifier = true
            }

        case .keyDown:
            // Le pressioni dei tasti modificatori arrivano come flagsChanged;
            // se mai arrivassero anche come keyDown, non devono bloccare il gesto.
            if event.keyCode == 59 || event.keyCode == 62 { return }
            if controlDown { usedAsModifier = true }

        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            if controlDown { usedAsModifier = true }

        default:
            break
        }
    }

    private func centerFrontWindow() {
        guard isEnabled,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular,
              let window = AX.focusedWindow(pid: app.processIdentifier),
              let raw = AX.frame(window) else { return }

        let frame = ScreenGeometry.appKit(fromAccessibility: raw)
        let center = NSPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else {
            return
        }

        let target = Centering.frame(for: frame, in: screen.visibleFrame)
        AX.setFrame(window, ScreenGeometry.accessibility(fromAppKit: target))
        AX.activate(window)
        onCentered?(app.processIdentifier, window)
    }
}
