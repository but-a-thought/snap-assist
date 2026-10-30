import AppKit

/// FancyZones-style placement: tieni premuto Shift e trascina una finestra
/// dalla barra del titolo; le zone del layout attivo compaiono in overlay e
/// il rilascio porta la finestra nella zona sotto il puntatore.
final class ZoneDragController {
    var isEnabled = true
    var onDragStateChanged: ((Bool) -> Void)?
    var onWindowPlaced: ((pid_t, AXUIElement) -> Void)?

    private struct Session {
        let pid: pid_t
        let window: AXUIElement
        let startMouse: NSPoint
        var active: Bool
    }

    private var timer: Timer?
    private var wasDown = false
    private var session: Session?
    private var overlay: ZoneOverlayPanel?
    private var overlayView: ZoneOverlayView?
    private var overlayScreen: NSScreen?
    private var highlighted: Int?

    func start() {
        stop()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        finish(cancelled: true)
    }

    // MARK: - Rilevamento

    private func tick() {
        guard isEnabled else { return }

        let shift = NSEvent.modifierFlags.contains(.shift)
        let down = (NSEvent.pressedMouseButtons & 0x1) != 0
        let mouse = NSEvent.mouseLocation

        if !down || !shift {
            if session != nil { finish(cancelled: true) }
            wasDown = down
            return
        }

        if !wasDown {
            wasDown = true
            begin(at: mouse)
        } else if var current = session {
            if !current.active {
                let dx = mouse.x - current.startMouse.x
                let dy = mouse.y - current.startMouse.y
                if dx * dx + dy * dy > 16 {
                    current.active = true
                    session = current
                    activate(current, at: mouse)
                }
            } else {
                update(at: mouse)
            }
        } else {
            // Shift premuto dopo aver iniziato a trascinare.
            begin(at: mouse)
        }
    }

    private func begin(at mouse: NSPoint) {
        session = nil
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular,
              let window = AX.focusedWindow(pid: app.processIdentifier),
              let raw = AX.frame(window) else { return }

        let frame = ScreenGeometry.appKit(fromAccessibility: raw)
        guard mouse.x >= frame.minX,
              mouse.x <= frame.maxX,
              mouse.y <= frame.maxY,
              mouse.y >= frame.maxY - 36,
              screen(containing: mouse) != nil else { return }

        session = Session(pid: app.processIdentifier, window: window, startMouse: mouse, active: false)
    }

    private func activate(_ session: Session, at mouse: NSPoint) {
        guard let screen = screen(containing: mouse) else { return }
        onDragStateChanged?(true)
        showOverlay(on: screen)
        update(at: mouse)
    }

    private func update(at mouse: NSPoint) {
        guard let session, session.active, let screen = screen(containing: mouse) else { return }

        if overlayScreen?.frame != screen.frame {
            showOverlay(on: screen)
        }

        let rects = LayoutStore.current.rects(in: screen)
        let index = rects.firstIndex { $0.contains(mouse) }
        highlighted = index

        let visible = screen.visibleFrame
        overlayView?.zones = rects.map { $0.offsetBy(dx: -visible.minX, dy: -visible.minY) }
        overlayView?.highlighted = index
        overlayView?.needsDisplay = true
    }

    private func finish(cancelled: Bool) {
        guard let session else {
            hideOverlay()
            return
        }

        if !cancelled, session.active,
           let screen = overlayScreen,
           let index = highlighted {
            let rects = LayoutStore.current.rects(in: screen)
            if rects.indices.contains(index) {
                let target = ScreenGeometry.accessibility(fromAppKit: rects[index])
                let window = session.window
                let pid = session.pid
                // Lasciamo finire il drag dell'app prima di imporre il frame.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    AX.setFrame(window, target)
                    self?.onWindowPlaced?(pid, window)
                }
            }
        }

        hideOverlay()
        self.session = nil
        if session.active {
            onDragStateChanged?(false)
        }
    }

    // MARK: - Overlay

    private func showOverlay(on screen: NSScreen) {
        if overlayScreen?.frame == screen.frame, let overlay {
            overlay.orderFrontRegardless()
            return
        }
        hideOverlay()

        let visible = screen.visibleFrame
        let panel = ZoneOverlayPanel(
            contentRect: visible,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = ZoneOverlayView(frame: NSRect(origin: .zero, size: visible.size))
        panel.contentView = view
        panel.orderFrontRegardless()

        overlay = panel
        overlayView = view
        overlayScreen = screen
        highlighted = nil
    }

    private func hideOverlay() {
        overlay?.orderOut(nil)
        overlay = nil
        overlayView = nil
        overlayScreen = nil
        highlighted = nil
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}

final class ZoneOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ZoneOverlayView: NSView {
    var zones: [NSRect] = []
    var highlighted: Int?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.16).setFill()
        bounds.fill()

        for (index, zone) in zones.enumerated() {
            let path = NSBezierPath(roundedRect: zone.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
            let isHighlighted = index == highlighted

            (isHighlighted
                ? NSColor.controlAccentColor.withAlphaComponent(0.34)
                : NSColor.white.withAlphaComponent(0.10)
            ).setFill()
            path.fill()

            (isHighlighted
                ? NSColor.white
                : NSColor.white.withAlphaComponent(0.45)
            ).setStroke()
            path.lineWidth = isHighlighted ? 2.5 : 1
            path.stroke()
        }
    }
}
