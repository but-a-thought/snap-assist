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

    /// Griglia con colonne e righe di dimensioni arbitrarie (frazioni di 1).
    static func custom(columns: [CGFloat], rows: [CGFloat]) -> ZoneLayout {
        let columns = normalized(columns)
        let rows = normalized(rows)
        var zones: [CGRect] = []
        var y: CGFloat = 0
        for row in rows {
            var x: CGFloat = 0
            for column in columns {
                zones.append(CGRect(x: x, y: y, width: column, height: row))
                x += column
            }
            y += row
        }
        return ZoneLayout(name: "Custom \(columns.count)×\(rows.count)", zones: zones)
    }

    /// Ricostruisce colonne e righe se le zone formano una griglia regolare.
    func gridComponents() -> (columns: [CGFloat], rows: [CGFloat])? {
        let xs = Array(Set(zones.flatMap { [Self.rounded($0.minX), Self.rounded($0.maxX)] })).sorted()
        let ys = Array(Set(zones.flatMap { [Self.rounded($0.minY), Self.rounded($0.maxY)] })).sorted()
        guard xs.count >= 2, ys.count >= 2 else { return nil }
        guard zones.count == (xs.count - 1) * (ys.count - 1) else { return nil }

        for i in 0..<(xs.count - 1) {
            for j in 0..<(ys.count - 1) {
                let center = CGPoint(x: (xs[i] + xs[i + 1]) / 2, y: (ys[j] + ys[j + 1]) / 2)
                guard zones.contains(where: {
                    $0.insetBy(dx: -0.002, dy: -0.002).contains(center)
                }) else { return nil }
            }
        }

        let columns = zip(xs, xs.dropFirst()).map { $1 - $0 }
        let rows = zip(ys, ys.dropFirst()).map { $1 - $0 }
        return (columns, rows)
    }

    private static func normalized(_ values: [CGFloat]) -> [CGFloat] {
        let total = values.reduce(0, +)
        guard total > 0 else { return [1] }
        return values.map { $0 / total }
    }

    private static func rounded(_ value: CGFloat) -> CGFloat {
        (value * 1000).rounded() / 1000
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
