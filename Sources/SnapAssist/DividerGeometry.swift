import AppKit

enum DividerOrientation: String {
    case vertical
    case horizontal
}

/// Geometria delle barre tra finestre adiacenti, anche per quarti e griglie.
enum DividerGeometry {
    struct PlacedWindow {
        let id: CGWindowID
        let pid: pid_t
        let rect: NSRect
    }

    struct Pair {
        /// Sinistra per una barra verticale, sopra per una orizzontale.
        let first: PlacedWindow
        let firstRect: NSRect
        let second: PlacedWindow
        let secondRect: NSRect
        let orientation: DividerOrientation

        var id: String {
            "\(first.id)-\(second.id)-\(orientation.rawValue)"
        }
    }

    /// Coppie di finestre adiacenti con bordi allineati, su tutti gli schermi.
    static func detectPairs(windows: [PlacedWindow], screens: [NSScreen]) -> [Pair] {
        guard windows.count >= 2 else { return [] }

        var result: [Pair] = []
        var seen = Set<String>()

        for screen in screens {
            for base in [screen.visibleFrame, screen.frame] {
                guard base.width > 300, base.height > 300 else { continue }

                for i in windows.indices {
                    for j in windows.indices where j > i {
                        let a = windows[i]
                        let b = windows[j]
                        let pair = verticalPair(a, b, base: base) ?? horizontalPair(a, b, base: base)
                        guard let pair, !seen.contains(pair.id) else { continue }
                        seen.insert(pair.id)
                        result.append(pair)
                    }
                }
            }
        }

        return result
    }

    private static func verticalPair(_ a: PlacedWindow, _ b: PlacedWindow, base: NSRect) -> Pair? {
        let left = a.rect.minX <= b.rect.minX ? a : b
        let right = a.rect.minX <= b.rect.minX ? b : a
        let l = left.rect
        let r = right.rect

        guard abs(l.maxX - r.minX) <= 24 else { return nil }
        guard abs(l.minY - r.minY) <= 24 else { return nil }
        guard abs(l.height - r.height) <= max(24, l.height * 0.06) else { return nil }
        guard l.width >= base.width * 0.12, r.width >= base.width * 0.12 else { return nil }
        guard l.height >= base.height * 0.2 else { return nil }
        guard l.minX >= base.minX - 24, r.maxX <= base.maxX + 24 else { return nil }
        guard l.minY >= base.minY - 24, l.maxY <= base.maxY + 24 else { return nil }

        return Pair(first: left, firstRect: l, second: right, secondRect: r, orientation: .vertical)
    }

    private static func horizontalPair(_ a: PlacedWindow, _ b: PlacedWindow, base: NSRect) -> Pair? {
        let top = a.rect.minY >= b.rect.minY ? a : b
        let bottom = a.rect.minY >= b.rect.minY ? b : a
        let t = top.rect
        let b = bottom.rect

        guard abs(t.minY - b.maxY) <= 24 else { return nil }
        guard abs(t.minX - b.minX) <= 24 else { return nil }
        guard abs(t.width - b.width) <= max(24, t.width * 0.06) else { return nil }
        guard t.height >= base.height * 0.12, b.height >= base.height * 0.12 else { return nil }
        guard t.width >= base.width * 0.2 else { return nil }
        guard t.minX >= base.minX - 24, t.maxX <= base.maxX + 24 else { return nil }
        guard b.minY >= base.minY - 24, t.maxY <= base.maxY + 24 else { return nil }

        return Pair(first: top, firstRect: t, second: bottom, secondRect: b, orientation: .horizontal)
    }

    static func dividerRect(for pair: Pair) -> NSRect {
        switch pair.orientation {
        case .vertical:
            let centerX = (pair.firstRect.maxX + pair.secondRect.minX) / 2
            let bottom = max(pair.firstRect.minY, pair.secondRect.minY)
            let top = min(pair.firstRect.maxY, pair.secondRect.maxY)
            let width: CGFloat = 12
            return NSRect(
                x: centerX - width / 2,
                y: bottom,
                width: width,
                height: top - bottom
            ).integral

        case .horizontal:
            let centerY = (pair.firstRect.minY + pair.secondRect.maxY) / 2
            let left = max(pair.firstRect.minX, pair.secondRect.minX)
            let right = min(pair.firstRect.maxX, pair.secondRect.maxX)
            let height: CGFloat = 12
            return NSRect(
                x: left,
                y: centerY - height / 2,
                width: right - left,
                height: height
            ).integral
        }
    }

    /// True se una finestra davanti alla coppia copre il confine.
    static func isCovered(pair: Pair, windows: [PlacedWindow]) -> Bool {
        let rect = dividerRect(for: pair)
        guard let firstIndex = windows.firstIndex(where: { $0.id == pair.first.id }),
              let secondIndex = windows.firstIndex(where: { $0.id == pair.second.id }) else {
            return true
        }
        let frontmostPairIndex = min(firstIndex, secondIndex)
        return windows.prefix(frontmostPairIndex).contains { $0.rect.intersects(rect) }
    }

    /// La barra compare solo quando il puntatore è praticamente sul confine
    /// (8 px), così non appare mentre si usa una sidebar o si passa vicino.
    static func shouldReveal(pair: Pair, mouse: NSPoint) -> Bool {
        let rect = dividerRect(for: pair)
        let proximity: CGFloat = 8
        switch pair.orientation {
        case .vertical:
            return abs(mouse.x - rect.midX) <= proximity
                && mouse.y >= rect.minY - 8
                && mouse.y <= rect.maxY + 8
        case .horizontal:
            return abs(mouse.y - rect.midY) <= proximity
                && mouse.x >= rect.minX - 8
                && mouse.x <= rect.maxX + 8
        }
    }

    /// Nuovi frame delle due finestre dato il punto di divisione.
    static func splitFrames(
        for pair: Pair,
        at value: CGFloat,
        minimum: CGFloat = 120
    ) -> (first: NSRect, second: NSRect)? {
        switch pair.orientation {
        case .vertical:
            let left = pair.firstRect
            let right = pair.secondRect
            guard right.maxX - left.minX > minimum * 2 else { return nil }
            let x = min(max(value, left.minX + minimum), right.maxX - minimum)
            return (
                NSRect(x: left.minX, y: left.minY, width: x - left.minX, height: left.height),
                NSRect(x: x, y: right.minY, width: right.maxX - x, height: right.height)
            )

        case .horizontal:
            let top = pair.firstRect
            let bottom = pair.secondRect
            guard top.maxY - bottom.minY > minimum * 2 else { return nil }
            let y = min(max(value, bottom.minY + minimum), top.maxY - minimum)
            return (
                NSRect(x: top.minX, y: y, width: top.width, height: top.maxY - y),
                NSRect(x: bottom.minX, y: bottom.minY, width: bottom.width, height: y - bottom.minY)
            )
        }
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
