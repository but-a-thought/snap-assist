import AppKit

/// Barra tra due finestre adiacenti (metà o quarti): trascinandola si
/// ridimensionano entrambe. Una sola barra alla volta, quella più vicina al
/// puntatore; non compare sopra altre finestre o in Mission Control.
final class DividerController {
    var onDraggingChanged: ((Bool) -> Void)?

    var isEnabled = true {
        didSet { if !isEnabled { hide() } }
    }

    var isSuspended = false {
        didSet { if isSuspended { hide() } }
    }

    private struct Active {
        let pair: DividerGeometry.Pair
        let first: AXUIElement
        let second: AXUIElement
    }

    private var timer: Timer?
    private var panel: DividerPanel?
    private var view: DividerView?
    private var displayedPair: DividerGeometry.Pair?
    private var active: Active?
    private var dragging = false

    func start() {
        stop()
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
        hide()
        active = nil
        dragging = false
    }

    private func tick() {
        guard isEnabled, !isSuspended else { return }

        if WindowList.isSystemOverlayActive() {
            hide()
            return
        }

        guard !dragging else { return }

        let windows = WindowList.allVisibleWindows().map { window in
            DividerGeometry.PlacedWindow(
                id: window.id,
                pid: window.pid,
                rect: ScreenGeometry.appKit(fromAccessibility: window.frame)
            )
        }
        let pairs = DividerGeometry.detectPairs(windows: windows, screens: NSScreen.screens)

        let mouse = NSEvent.mouseLocation

        let candidates = pairs.filter { pair in
            !DividerGeometry.isCovered(pair: pair, windows: windows)
                && DividerGeometry.shouldReveal(pair: pair, mouse: mouse)
        }

        guard let best = candidates.min(by: {
            distance(from: $0, to: mouse) < distance(from: $1, to: mouse)
        }) else {
            hide()
            return
        }

        show(best, mouse: mouse)
    }

    private func distance(from pair: DividerGeometry.Pair, to point: NSPoint) -> CGFloat {
        let rect = DividerGeometry.dividerRect(for: pair)
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    private func show(_ pair: DividerGeometry.Pair, mouse: NSPoint) {
        displayedPair = pair
        let rect = DividerGeometry.dividerRect(for: pair)
        let panel = ensurePanel()

        if panel.frame != rect {
            panel.setFrame(rect, display: true)
        }
        view?.orientation = pair.orientation
        view?.pointerInside = pointerIsInside(mouse, rect: rect, orientation: pair.orientation)
        view?.needsDisplay = true

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func pointerIsInside(
        _ mouse: NSPoint,
        rect: NSRect,
        orientation: DividerOrientation
    ) -> Bool {
        switch orientation {
        case .vertical:
            return abs(mouse.x - rect.midX) <= 10
                && mouse.y >= rect.minY - 4
                && mouse.y <= rect.maxY + 4
        case .horizontal:
            return abs(mouse.y - rect.midY) <= 10
                && mouse.x >= rect.minX - 4
                && mouse.x <= rect.maxX + 4
        }
    }

    private func hide() {
        panel?.orderOut(nil)
        displayedPair = nil
    }

    // MARK: - Pannello

    private func ensurePanel() -> DividerPanel {
        if let panel { return panel }

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
        view.onDragBegan = { [weak self] in self?.beginDrag() }
        view.onDrag = { [weak self] point in self?.drag(to: point) }
        view.onDragEnded = { [weak self] in self?.endDrag() }
        panel.contentView = view

        self.panel = panel
        self.view = view
        return panel
    }

    // MARK: - Trascinamento

    private func beginDrag() {
        guard let pair = displayedPair else { return }
        guard let first = AX.window(
            pid: pair.first.pid,
            matching: ScreenGeometry.accessibility(fromAppKit: pair.firstRect)
        ), let second = AX.window(
            pid: pair.second.pid,
            matching: ScreenGeometry.accessibility(fromAppKit: pair.secondRect)
        ) else { return }

        active = Active(pair: pair, first: first, second: second)
        dragging = true
        onDraggingChanged?(true)
    }

    private func drag(to point: NSPoint) {
        guard let active else { return }
        let value = active.pair.orientation == .vertical ? point.x : point.y
        guard let frames = DividerGeometry.splitFrames(
            for: active.pair,
            at: value
        ) else { return }

        AX.setFrame(active.first, ScreenGeometry.accessibility(fromAppKit: frames.first))
        AX.setFrame(active.second, ScreenGeometry.accessibility(fromAppKit: frames.second))

        if let panel {
            switch active.pair.orientation {
            case .vertical:
                panel.setFrameOrigin(NSPoint(
                    x: value - panel.frame.width / 2,
                    y: panel.frame.minY
                ))
            case .horizontal:
                panel.setFrameOrigin(NSPoint(
                    x: panel.frame.minX,
                    y: value - panel.frame.height / 2
                ))
            }
        }
    }

    private func endDrag() {
        guard dragging else { return }
        dragging = false
        active = nil
        onDraggingChanged?(false)
        tick()
    }
}

// MARK: - Vista

final class DividerView: NSView {
    var onDragBegan: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    var orientation: DividerOrientation = .vertical {
        didSet { needsDisplay = true }
    }

    /// Solo per la modalità demo: mostra la maniglia senza passare il mouse.
    var previewHighlight = false {
        didSet { needsDisplay = true }
    }

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
        switch orientation {
        case .vertical:
            NSColor.black.withAlphaComponent(0.25).setFill()
            NSRect(x: bounds.midX - 1.5, y: 0, width: 3, height: bounds.height).fill()
            NSColor.white.withAlphaComponent(0.70).setFill()
            NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()

        case .horizontal:
            NSColor.black.withAlphaComponent(0.25).setFill()
            NSRect(x: 0, y: bounds.midY - 1.5, width: bounds.width, height: 3).fill()
            NSColor.white.withAlphaComponent(0.70).setFill()
            NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1).fill()
        }

        guard hovered || dragging || previewHighlight || pointerInside else { return }

        let grip: NSRect
        switch orientation {
        case .vertical:
            grip = NSRect(x: bounds.midX - 3.5, y: bounds.midY - 28, width: 7, height: 56)
        case .horizontal:
            grip = NSRect(x: bounds.midX - 28, y: bounds.midY - 3.5, width: 56, height: 7)
        }

        let path = NSBezierPath(roundedRect: grip, xRadius: 3.5, yRadius: 3.5)
        NSColor(calibratedWhite: 0.16, alpha: 0.95).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        NSColor.white.withAlphaComponent(0.85).setFill()
        for offset: CGFloat in [-8, 0, 8] {
            let dot: NSRect
            switch orientation {
            case .vertical:
                dot = NSRect(x: bounds.midX - 1, y: bounds.midY + offset - 1, width: 2, height: 2)
            case .horizontal:
                dot = NSRect(x: bounds.midX + offset - 1, y: bounds.midY - 1, width: 2, height: 2)
            }
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        dragging = false
        onDragEnded?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: orientation == .vertical ? .resizeLeftRight : .resizeUpDown)
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
