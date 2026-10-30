import AppKit

/// Editor libero delle zone: trascina sul canvas per disegnare un rettangolo,
/// trascina dentro una zona per spostarla, sui bordi per ridimensionarla.
final class CustomLayoutEditorView: NSView {
    private(set) var zones: [CGRect] = []
    var selectedIndex: Int?
    var onChange: ((ZoneLayout) -> Void)?
    var selected = false {
        didSet { needsDisplay = true }
    }

    private enum Drag {
        case draw(CGPoint)
        case move(index: Int, start: CGPoint, original: CGRect)
        case resize(index: Int, start: CGPoint, original: CGRect)
    }

    private var drag: Drag?
    private var draft: CGRect?
    private var trackingArea: NSTrackingArea?

    var layout: ZoneLayout {
        ZoneLayout(name: "Custom", zones: zones)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - API

    func setZones(_ zones: [CGRect], notify: Bool = false) {
        self.zones = zones
        selectedIndex = nil
        needsDisplay = true
        if notify, !zones.isEmpty { onChange?(layout) }
    }

    func applyGrid(columns: Int, rows: Int) {
        setZones(ZoneLayout.grid(columns: columns, rows: rows).zones, notify: true)
    }

    func clear() {
        zones = []
        selectedIndex = nil
        needsDisplay = true
    }

    func deleteSelected() {
        guard let selectedIndex, zones.indices.contains(selectedIndex) else { return }
        zones.remove(at: selectedIndex)
        self.selectedIndex = nil
        needsDisplay = true
        if !zones.isEmpty { onChange?(layout) }
    }

    // MARK: - Geometria

    private var area: NSRect {
        bounds.insetBy(dx: 16, dy: 16)
    }

    private func normalized(_ point: NSPoint) -> CGPoint {
        let x = (point.x - area.minX) / area.width
        let y = (area.maxY - point.y) / area.height
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    private func snap(_ value: CGFloat) -> CGFloat {
        (value * 50).rounded() / 50
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let x = min(start.x, end.x)
        let y = min(start.y, end.y)
        return CGRect(
            x: snap(x),
            y: snap(y),
            width: snap(max(0, abs(end.x - start.x))),
            height: snap(max(0, abs(end.y - start.y)))
        )
    }

    private func viewRect(_ zone: CGRect) -> NSRect {
        NSRect(
            x: area.minX + zone.minX * area.width,
            y: area.maxY - (zone.minY + zone.height) * area.height,
            width: zone.width * area.width,
            height: zone.height * area.height
        )
    }

    private func overlaps(_ rect: CGRect, ignoring index: Int?) -> Bool {
        let probe = rect.insetBy(dx: 0.002, dy: 0.002)
        for (zoneIndex, zone) in zones.enumerated() where zoneIndex != index {
            if zone.insetBy(dx: 0.002, dy: 0.002).intersects(probe) { return true }
        }
        return false
    }

    // MARK: - Disegno

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.withAlphaComponent(0.45).setFill()
        background.fill()

        // Griglia di riferimento leggera.
        NSColor.secondaryLabelColor.withAlphaComponent(0.08).setStroke()
        for step in 1..<10 {
            let x = area.minX + area.width * CGFloat(step) / 10
            let y = area.minY + area.height * CGFloat(step) / 10
            let v = NSBezierPath()
            v.move(to: NSPoint(x: x, y: area.minY))
            v.line(to: NSPoint(x: x, y: area.maxY))
            v.lineWidth = 0.5
            v.stroke()
            let h = NSBezierPath()
            h.move(to: NSPoint(x: area.minX, y: y))
            h.line(to: NSPoint(x: area.maxX, y: y))
            h.lineWidth = 0.5
            h.stroke()
        }

        for (index, zone) in zones.enumerated() {
            let rect = viewRect(zone).insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            let isSelected = index == selectedIndex && selected
            NSColor.controlAccentColor.withAlphaComponent(isSelected ? 0.28 : 0.13).setFill()
            path.fill()
            (isSelected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor.withAlphaComponent(0.45)).setStroke()
            path.lineWidth = isSelected ? 2 : 1
            path.stroke()

            if isSelected {
                for point in [
                    NSPoint(x: rect.minX, y: rect.minY),
                    NSPoint(x: rect.maxX, y: rect.minY),
                    NSPoint(x: rect.minX, y: rect.maxY),
                    NSPoint(x: rect.maxX, y: rect.maxY)
                ] {
                    let handle = NSRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
                    NSColor.controlAccentColor.setFill()
                    NSBezierPath(ovalIn: handle).fill()
                }
            }
        }

        if let draft {
            let rect = viewRect(draft)
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.stroke()
        }

        if zones.isEmpty, draft == nil {
            let text = L10n.t("layout.drawHint")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                withAttributes: attributes
            )
        }

        if selected {
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
            NSColor.controlAccentColor.setStroke()
            border.lineWidth = 2
            border.stroke()
        }
    }

    // MARK: - Interazione

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = normalized(convert(event.locationInWindow, from: nil))

        if let index = zones.indices.last(where: { zones[$0].contains(point) }) {
            selectedIndex = index
            selected = true
            let zone = zones[index]
            let edge: CGFloat = 0.018
            let nearEdge = abs(point.x - zone.minX) < edge
                || abs(point.x - zone.maxX) < edge
                || abs(point.y - zone.minY) < edge
                || abs(point.y - zone.maxY) < edge
            drag = nearEdge
                ? .resize(index: index, start: point, original: zone)
                : .move(index: index, start: point, original: zone)
        } else {
            selectedIndex = nil
            drag = .draw(point)
            draft = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = normalized(convert(event.locationInWindow, from: nil))

        switch drag {
        case .draw(let start):
            draft = normalizedRect(from: start, to: point)

        case .move(let index, let start, let original):
            let dx = point.x - start.x
            let dy = point.y - start.y
            var moved = original.offsetBy(dx: dx, dy: dy)
            moved.origin.x = min(max(moved.origin.x, 0), 1 - moved.width)
            moved.origin.y = min(max(moved.origin.y, 0), 1 - moved.height)
            moved.origin.x = snap(moved.origin.x)
            moved.origin.y = snap(moved.origin.y)
            if !overlaps(moved, ignoring: index) {
                zones[index] = moved
                onChange?(layout)
            }

        case .resize(let index, let start, let original):
            var resized = original
            let edge: CGFloat = 0.018
            if abs(start.x - original.minX) < edge {
                let newX = min(point.x, original.maxX - 0.04)
                resized.origin.x = newX
                resized.size.width = original.maxX - newX
            }
            if abs(start.x - original.maxX) < edge {
                resized.size.width = max(0.04, point.x - original.minX)
            }
            if abs(start.y - original.minY) < edge {
                let newY = min(point.y, original.maxY - 0.04)
                resized.origin.y = newY
                resized.size.height = original.maxY - newY
            }
            if abs(start.y - original.maxY) < edge {
                resized.size.height = max(0.04, point.y - original.minY)
            }
            resized.origin.x = snap(min(max(resized.origin.x, 0), 1))
            resized.origin.y = snap(min(max(resized.origin.y, 0), 1))
            resized.size.width = snap(min(resized.size.width, 1 - resized.origin.x))
            resized.size.height = snap(min(resized.size.height, 1 - resized.origin.y))
            if !overlaps(resized, ignoring: index) {
                zones[index] = resized
                onChange?(layout)
            }
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if case .draw = drag, let draft {
            if draft.width >= 0.03, draft.height >= 0.03, !overlaps(draft, ignoring: nil) {
                zones.append(draft)
                selectedIndex = zones.count - 1
                onChange?(layout)
            } else {
                NSSound.beep()
            }
            self.draft = nil
        }
        drag = nil
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelected()
        } else {
            super.keyDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = normalized(convert(event.locationInWindow, from: nil))
        if let index = zones.indices.last(where: { zones[$0].contains(point) }) {
            let zone = zones[index]
            let edge: CGFloat = 0.018
            if abs(point.x - zone.minX) < edge || abs(point.x - zone.maxX) < edge {
                NSCursor.resizeLeftRight.set()
            } else if abs(point.y - zone.minY) < edge || abs(point.y - zone.maxY) < edge {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.openHand.set()
            }
        } else {
            NSCursor.crosshair.set()
        }
    }
}
