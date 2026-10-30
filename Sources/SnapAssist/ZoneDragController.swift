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
    private var monitors: [Any] = []
    private var wasDown = false
    private var session: Session?
    private var overlay: ZoneOverlayPanel?
    private var overlayView: ZoneOverlayView?
    private var overlayScreen: NSScreen?
    private var highlighted: Int?
    private var lastBeginFailure = ""

    func start() {
        stop()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // I monitor globali rendono il rilevamento più affidabile durante il
        // drag di un'altra app; il timer resta come fallback.
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handleGlobal(event)
        }) {
            monitors.append(monitor)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        finish(cancelled: true)
    }

    private func handleGlobal(_ event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let mouse = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown, .leftMouseDragged:
            handleState(down: true, shift: shift, mouse: mouse)
        case .leftMouseUp:
            handleState(down: false, shift: shift, mouse: mouse)
        case .flagsChanged:
            let down = (NSEvent.pressedMouseButtons & 0x1) != 0
            handleState(down: down, shift: shift, mouse: mouse)
        default:
            break
        }
    }

    // MARK: - Rilevamento

    private func tick() {
        let down = (NSEvent.pressedMouseButtons & 0x1) != 0
        let shift = NSEvent.modifierFlags.contains(.shift)
        handleState(down: down, shift: shift, mouse: NSEvent.mouseLocation)
    }

    private func handleState(down: Bool, shift: Bool, mouse: NSPoint) {
        guard isEnabled else { return }

        if !down {
            if session != nil {
                ZoneLog.write("rilascio: applico la zona")
                finish(cancelled: false)
            }
            wasDown = false
            lastBeginFailure = ""
            return
        }

        if !shift {
            if session != nil {
                ZoneLog.write("annullo: Shift rilasciato")
                finish(cancelled: true)
            }
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
        guard let app = NSWorkspace.shared.frontmostApplication else {
            fail("nessuna app in primo piano")
            return
        }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            fail("app stessa in primo piano")
            return
        }
        guard app.activationPolicy == .regular else {
            fail("app non regular")
            return
        }
        guard let window = AX.focusedWindow(pid: app.processIdentifier) else {
            fail("nessuna finestra in primo piano")
            return
        }
        guard let raw = AX.frame(window) else {
            fail("frame non leggibile")
            return
        }

        let frame = ScreenGeometry.appKit(fromAccessibility: raw)
        guard mouse.x >= frame.minX,
              mouse.x <= frame.maxX,
              mouse.y <= frame.maxY,
              mouse.y >= frame.maxY - 48,
              screen(containing: mouse) != nil else {
            fail("puntatore fuori dalla barra del titolo (mouse \(Int(mouse.x)),\(Int(mouse.y)) finestra \(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height)))")
            return
        }

        session = Session(pid: app.processIdentifier, window: window, startMouse: mouse, active: false)
        lastBeginFailure = ""
        ZoneLog.write("begin pid=\(app.processIdentifier) frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))")
    }

    private func fail(_ reason: String) {
        guard lastBeginFailure != reason else { return }
        lastBeginFailure = reason
        ZoneLog.write("begin failed: \(reason)")
    }

    private func activate(_ session: Session, at mouse: NSPoint) {
        guard let screen = screen(containing: mouse) else { return }
        ZoneLog.write("drag attivo su schermo \(screen.localizedName)")
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

        if !cancelled, session.active {
            let mouse = NSEvent.mouseLocation
            if let screen = screen(containing: mouse) ?? overlayScreen {
                let rects = LayoutStore.current.rects(in: screen)
                if let index = rects.firstIndex(where: { $0.contains(mouse) }) {
                    let rect = rects[index]
                    let target = ScreenGeometry.accessibility(fromAppKit: rect)
                    let window = session.window
                    let pid = session.pid
                    ZoneLog.write("drop zona \(index) -> \(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))")
                    // Lasciamo finire il drag dell'app prima di imporre il frame.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                        let moved = AX.setFrame(window, target)
                        ZoneLog.write("setFrame -> \(moved)")
                        self?.onWindowPlaced?(pid, window)
                    }
                } else {
                    ZoneLog.write("drop fuori dalle zone")
                }
            }
        } else if cancelled, session.active {
            ZoneLog.write("drag annullato")
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

/// Log leggero delle transizioni del drag con Shift (per diagnosi).
enum ZoneLog {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SnapAssist.log")

    static func write(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
