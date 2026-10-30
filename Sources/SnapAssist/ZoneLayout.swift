import AppKit

/// Un layout di zone in coordinate normalizzate (0…1, origine in alto a
/// sinistra). Viene mappato sul visibleFrame di ogni schermo.
struct ZoneLayout: Codable, Equatable {
    var name: String
    var zones: [CGRect]

    func rects(in screen: NSScreen, gap: CGFloat = 0) -> [NSRect] {
        let frame = screen.visibleFrame
        return zones.map { zone in
            let rect = NSRect(
                x: frame.minX + zone.minX * frame.width,
                y: frame.maxY - (zone.minY + zone.height) * frame.height,
                width: zone.width * frame.width,
                height: zone.height * frame.height
            )
            return gap > 0 ? rect.insetBy(dx: gap, dy: gap) : rect
        }
    }

    func zoneIndex(at point: NSPoint, in screen: NSScreen) -> Int? {
        rects(in: screen).firstIndex { $0.contains(point) }
    }

    static func grid(columns: Int, rows: Int) -> ZoneLayout {
        let columns = max(1, min(6, columns))
        let rows = max(1, min(4, rows))
        var zones: [CGRect] = []
        for row in 0..<rows {
            for column in 0..<columns {
                zones.append(CGRect(
                    x: CGFloat(column) / CGFloat(columns),
                    y: CGFloat(row) / CGFloat(rows),
                    width: 1 / CGFloat(columns),
                    height: 1 / CGFloat(rows)
                ))
            }
        }
        return ZoneLayout(name: "\(columns) × \(rows)", zones: zones)
    }

    static let presets: [ZoneLayout] = [
        ZoneLayout(name: "Halves", zones: [
            CGRect(x: 0, y: 0, width: 0.5, height: 1),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        ]),
        ZoneLayout(name: "Thirds", zones: [
            CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1),
            CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1),
            CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        ]),
        ZoneLayout(name: "Rows", zones: [
            CGRect(x: 0, y: 0, width: 1, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        ]),
        ZoneLayout(name: "2 × 2", zones: [
            CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
            CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        ]),
        ZoneLayout(name: "Main + stack", zones: [
            CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1),
            CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 0.5),
            CGRect(x: 2.0 / 3, y: 0.5, width: 1.0 / 3, height: 0.5)
        ]),
        ZoneLayout(name: "Stack + main", zones: [
            CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1),
            CGRect(x: 0, y: 0, width: 1.0 / 3, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 1.0 / 3, height: 0.5)
        ]),
        ZoneLayout(name: "3 × 2", zones: [
            CGRect(x: 0, y: 0, width: 1.0 / 3, height: 0.5),
            CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 0.5),
            CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 1.0 / 3, height: 0.5),
            CGRect(x: 1.0 / 3, y: 0.5, width: 1.0 / 3, height: 0.5),
            CGRect(x: 2.0 / 3, y: 0.5, width: 1.0 / 3, height: 0.5)
        ]),
        ZoneLayout(name: "Grid 2 × 3", zones: grid(columns: 2, rows: 3).zones)
    ]
}

enum LayoutStore {
    private static let key = "zoneLayout"

    static var current: ZoneLayout {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let layout = try? JSONDecoder().decode(ZoneLayout.self, from: data),
                  !layout.zones.isEmpty else {
                return ZoneLayout.presets[0]
            }
            return layout
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
