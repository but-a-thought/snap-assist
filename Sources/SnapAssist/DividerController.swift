import AppKit

/// Barra verticale tra due finestre affiancate: trascinandola si ridimensionano
/// entrambe in un colpo solo, come in Windows 11.
final class DividerController {
    /// Chiamata all'inizio e alla fine di un trascinamento della barra.
    var onDraggingChanged: ((Bool) -> Void)?

    var isEnabled = true {
        didSet { if !isEnabled { hideAll() } }
    }

    /// True mentre è aperto il pannello di scelta: la barra sparisce.
    var isSuspended = false {
        didSet { if isSuspended { hideAll() } }
    }

    private struct ActivePair {
        let left: AXUIElement
        let right: AXUIElement
        let leftRect: NSRect
        let rightRect: NSRect
        let displayID: CGDirectDisplayID
    }

    private var timer: Timer?
    private var panels: [CGDirectDisplayID: DividerPanel] = [:]
    private var detected: [CGDirectDisplayID: DividerGeometry.Pair] = [:]
    private var detectedWindows: [DividerGeometry.PlacedWindow] = []
    private var active: ActivePair?
    private var activeDisplayID: CGDirectDisplayID?
    private var dragging = false

    func start() {
        stop()
        // Frequenza alta: la barra deve comparire appena il puntatore si
        // avvicina al confine.
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hideAll()
    }

    func hideAll() {
        dragging = false
        active = nil
        activeDisplayID = nil
        for panel in panels.values {
            panel.orderOut(nil)
        }
    }

    // MARK: - Rilevamento

    private func tick() {
        guard isEnabled, !isSuspended else { return }

        if WindowList.isSystemOverlayActive() {
            hideAll()
            return
        }

        let pairs = detectPairs()
        detected = pairs

        let mouse = NSEvent.mouseLocation
        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let myPid = ProcessInfo.processInfo.processIdentifier

        for (id, panel) in panels where pairs[id] == nil {
            panel.orderOut(nil)
        }

        for (id, pair) in pairs {
            let panel = panel(for: id)
            let rect = DividerGeometry.dividerRect(for: pair)

            let shouldShow: Bool
            if dragging {
                shouldShow = id == activeDisplayID
            } else {
                let coveredByOtherWindow = DividerGeometry.isCovered(pair: pair, windows: detectedWindows)
                shouldShow = !coveredByOtherWindow && DividerGeometry.shouldReveal(
                    pair: pair,
                    mouse: mouse,
                    frontPid: frontPid,
                    myPid: myPid
                )
            }

            guard shouldShow else {
                panel.orderOut(nil)
                continue
            }

            if panel.frame != rect {
                panel.setFrame(rect, display: true)
            }
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
            (panel.contentView as? DividerView)?.pointerInside = abs(mouse.x - rect.midX) <= 10
        }
    }

    private func detectPairs() -> [CGDirectDisplayID: DividerGeometry.Pair] {
        let windows = WindowList.allVisibleWindows().map { window in
            DividerGeometry.PlacedWindow(
                id: window.id,
                pid: window.pid,
                rect: ScreenGeometry.appKit(fromAccessibility: window.frame)
            )
        }
        detectedWindows = windows
        return DividerGeometry.detectPairs(windows: windows, screens: NSScreen.screens)
    }

    // MARK: - Pannello

    private func panel(for displayID: CGDirectDisplayID) -> DividerPanel {
        if let existing = panels[displayID] { return existing }

        let panel = DividerPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = DividerView(frame: .zero)
        view.onDragBegan = { [weak self] in self?.beginDrag(displayID: displayID) }
        view.onDrag = { [weak self] x in self?.drag(to: x) }
        view.onDragEnded = { [weak self] in self?.endDrag() }
        panel.contentView = view

        panels[displayID] = panel
        return panel
    }

    // MARK: - Trascinamento

    private func beginDrag(displayID: CGDirectDisplayID) {
        guard let pair = detected[displayID],
              let left = AX.window(pid: pair.left.pid, matching: ScreenGeometry.accessibility(fromAppKit: pair.leftRect)),
              let right = AX.window(pid: pair.right.pid, matching: ScreenGeometry.accessibility(fromAppKit: pair.rightRect)) else { return }

        active = ActivePair(
            left: left,
            right: right,
            leftRect: pair.leftRect,
            rightRect: pair.rightRect,
            displayID: displayID
        )
        activeDisplayID = displayID
        dragging = true
        onDraggingChanged?(true)
    }

    private func drag(to screenX: CGFloat) {
        guard let pair = active,
              let frames = DividerGeometry.splitFrames(
                left: pair.leftRect,
                right: pair.rightRect,
                splitX: screenX
              ) else { return }

        // La finestra di sinistra cambia solo larghezza, quella di destra
        // cambia posizione e larghezza.
        AX.setSize(pair.left, frames.left.size)
        AX.setFrame(pair.right, ScreenGeometry.accessibility(fromAppKit: frames.right))

        if let panel = panels[pair.displayID] {
            panel.setFrameOrigin(NSPoint(x: frames.right.minX - panel.frame.width / 2, y: panel.frame.minY))
        }
    }

    private func endDrag() {
        guard dragging else { return }
        dragging = false
        active = nil
        activeDisplayID = nil
        onDraggingChanged?(false)
        tick()
    }
}

// MARK: - Vista

final class DividerView: NSView {
    var onDragBegan: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

    /// Solo per la modalità demo: mostra la maniglia senza passare il mouse.
    var previewHighlight = false {
        didSet { needsDisplay = true }
    }

    /// Impostato dal controller quando il puntatore è sulla barra.
    var pointerInside = false {
        didSet { if pointerInside != oldValue { needsDisplay = true } }
    }

    private var hovered = false {
        didSet { needsDisplay = true }
    }
    private var dragging = false {
        didSet { needsDisplay = true }
    }
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        // Linea sottile, leggibile sia su finestre chiare sia scure.
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSRect(x: bounds.midX - 1.5, y: 0, width: 3, height: bounds.height).fill()

        NSColor.white.withAlphaComponent(0.70).setFill()
        NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()

        guard hovered || dragging || previewHighlight || pointerInside else { return }

        let grip = NSRect(x: bounds.midX - 3.5, y: bounds.midY - 28, width: 7, height: 56)
        let path = NSBezierPath(roundedRect: grip, xRadius: 3.5, yRadius: 3.5)
        NSColor(calibratedWhite: 0.16, alpha: 0.95).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        NSColor.white.withAlphaComponent(0.85).setFill()
        for offset: CGFloat in [-8, 0, 8] {
            let dot = NSRect(x: bounds.midX - 1, y: bounds.midY + offset - 1, width: 2, height: 2)
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(NSEvent.mouseLocation.x)
    }

    override func mouseUp(with event: NSEvent) {
        dragging = false
        onDragEnded?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }
}

final class DividerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
