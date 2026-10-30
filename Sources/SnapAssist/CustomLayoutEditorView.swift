import AppKit

/// Canvas dell'editor: griglia con divisori trascinabili per definire
/// liberamente la dimensione delle zone.
final class CustomLayoutEditorView: NSView {
    var columns: [CGFloat] = [0.5, 0.5] {
        didSet { needsDisplay = true }
    }
    var rows: [CGFloat] = [1] {
        didSet { needsDisplay = true }
    }
    var selected = false {
        didSet { needsDisplay = true }
    }
    var onChange: ((ZoneLayout) -> Void)?

    private enum Drag {
        case vertical(Int)
        case horizontal(Int)
    }

    private var drag: Drag?
    private var trackingArea: NSTrackingArea?

    var layout: ZoneLayout {
        .custom(columns: columns, rows: rows)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setGrid(columns: Int, rows: Int) {
        let columns = max(1, min(6, columns))
        let rows = max(1, min(4, rows))
        self.columns = Array(repeating: 1 / CGFloat(columns), count: columns)
        self.rows = Array(repeating: 1 / CGFloat(rows), count: rows)
        drag = nil
        onChange?(layout)
    }

    func apply(_ layout: ZoneLayout) {
        guard let components = layout.gridComponents() else { return }
        columns = components.columns
        rows = components.rows
    }

    // MARK: - Geometria

    private var area: NSRect {
        bounds.insetBy(dx: 14, dy: 14)
    }

    private func columnEdges() -> [CGFloat] {
        var edges = [area.minX]
        var x = area.minX
        for column in columns {
            x += column * area.width
            edges.append(x)
        }
        return edges
    }

    private func rowEdges() -> [CGFloat] {
        var edges = [area.maxY]
        var y = area.maxY
        for row in rows {
            y -= row * area.height
            edges.append(y)
        }
        return edges
    }

    // MARK: - Disegno

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.withAlphaComponent(0.45).setFill()
        background.fill()

        let xs = columnEdges()
        let ys = rowEdges()

        for column in 0..<max(1, columns.count) {
            for row in 0..<max(1, rows.count) {
                let rect = NSRect(
                    x: xs[column],
                    y: ys[row + 1],
                    width: xs[column + 1] - xs[column],
                    height: ys[row] - ys[row + 1]
                ).insetBy(dx: 3, dy: 3)
                let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
                NSColor.controlAccentColor.withAlphaComponent(selected ? 0.22 : 0.10).setFill()
                path.fill()
                NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }

        // Divisori trascinabili.
        let handleColor = NSColor.controlAccentColor.withAlphaComponent(selected ? 0.9 : 0.55)
        for index in 1..<columns.count {
            let x = xs[index]
            let handle = NSRect(x: x - 2, y: area.midY - 16, width: 4, height: 32)
            handleColor.setFill()
            NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2).fill()
        }
        for index in 1..<rows.count {
            let y = ys[index]
            let handle = NSRect(x: area.midX - 16, y: y - 2, width: 32, height: 4)
            handleColor.setFill()
            NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2).fill()
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
        let point = convert(event.locationInWindow, from: nil)
        let xs = columnEdges()
        let ys = rowEdges()

        for index in 1..<columns.count where abs(point.x - xs[index]) < 8 {
            drag = .vertical(index)
            return
        }
        for index in 1..<rows.count where abs(point.y - ys[index]) < 8 {
            drag = .horizontal(index)
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let minimum: CGFloat = 0.06

        switch drag {
        case .vertical(let index):
            let sumBefore = columns[0..<(index - 1)].reduce(0, +)
            let pair = columns[index - 1] + columns[index]
            guard pair > minimum * 2 else { return }
            let target = (point.x - area.minX) / area.width
            let left = min(max(target - sumBefore, minimum), pair - minimum)
            columns[index - 1] = left
            columns[index] = pair - left

        case .horizontal(let index):
            let sumBefore = rows[0..<(index - 1)].reduce(0, +)
            let pair = rows[index - 1] + rows[index]
            guard pair > minimum * 2 else { return }
            let target = (area.maxY - point.y) / area.height
            let top = min(max(target - sumBefore, minimum), pair - minimum)
            rows[index - 1] = top
            rows[index] = pair - top
        }

        needsDisplay = true
        onChange?(layout)
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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
        let point = convert(event.locationInWindow, from: nil)
        let xs = columnEdges()
        let ys = rowEdges()

        if (1..<columns.count).contains(where: { abs(point.x - xs[$0]) < 8 }) {
            NSCursor.resizeLeftRight.set()
        } else if (1..<rows.count).contains(where: { abs(point.y - ys[$0]) < 8 }) {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}
