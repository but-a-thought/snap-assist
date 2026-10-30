import AppKit

/// Geometria della barra tra finestre affiancate, separata dal controller così
/// da poter essere verificata con finestre simulate.
enum DividerGeometry {
    struct PlacedWindow {
        let id: CGWindowID
        let pid: pid_t
        let rect: NSRect
    }

    struct Pair {
        let left: PlacedWindow
        let leftRect: NSRect
        let right: PlacedWindow
        let rightRect: NSRect
    }

    /// Coppie di finestre affiancate a tutta altezza, una per schermo.
    static func detectPairs(windows: [PlacedWindow], screens: [NSScreen]) -> [CGDirectDisplayID: Pair] {
        guard !windows.isEmpty else { return [:] }

        var result: [CGDirectDisplayID: Pair] = [:]

        for screen in screens {
            guard let id = displayID(for: screen) else { continue }

            for base in [screen.visibleFrame, screen.frame] {
                let minWidth = base.width * 0.18
                let maxWidth = base.width * 0.82
                let verticalTolerance = max(40, base.height * 0.12)

                let lefts = windows.filter { window in
                    abs(window.rect.minX - base.minX) <= 24
                        && window.rect.width >= minWidth && window.rect.width <= maxWidth
                        && abs(window.rect.minY - base.minY) <= verticalTolerance
                        && abs(window.rect.height - base.height) <= verticalTolerance
                }
                let rights = windows.filter { window in
                    abs(window.rect.maxX - base.maxX) <= 24
                        && window.rect.width >= minWidth && window.rect.width <= maxWidth
                        && abs(window.rect.minY - base.minY) <= verticalTolerance
                        && abs(window.rect.height - base.height) <= verticalTolerance
                }

                var found: Pair?
                for left in lefts {
                    for right in rights where right.id != left.id {
                        guard abs(left.rect.maxX - right.rect.minX) <= 32 else { continue }
                        let top = min(left.rect.maxY, right.rect.maxY)
                        let bottom = max(left.rect.minY, right.rect.minY)
                        guard top - bottom >= 120 else { continue }
                        found = Pair(left: left, leftRect: left.rect, right: right, rightRect: right.rect)
                        break
                    }
                    if found != nil { break }
                }

                if let found {
                    result[id] = found
                    break
                }
            }
        }

        return result
    }

    static func dividerRect(for pair: Pair) -> NSRect {
        let centerX = (pair.leftRect.maxX + pair.rightRect.minX) / 2
        let bottom = max(pair.leftRect.minY, pair.rightRect.minY)
        let top = min(pair.leftRect.maxY, pair.rightRect.maxY)
        let width: CGFloat = 12
        return NSRect(
            x: centerX - width / 2,
            y: bottom,
            width: width,
            height: top - bottom
        ).integral
    }

    /// La barra compare solo se il puntatore è vicino al confine e una delle
    /// due finestre (o l'app stessa) è in primo piano: non deve restare sopra
    /// a finestre di altre app.
    static func shouldReveal(pair: Pair, mouse: NSPoint, frontPid: pid_t?, myPid: pid_t) -> Bool {
        let rightAppInFront = frontPid == pair.left.pid
            || frontPid == pair.right.pid
            || frontPid == myPid
        guard rightAppInFront else { return false }

        let rect = dividerRect(for: pair)
        return mouse.x >= rect.minX - 30
            && mouse.x <= rect.maxX + 30
            && mouse.y >= rect.minY
            && mouse.y <= rect.maxY
    }

    /// Nuovi frame per le due finestre dato il punto di divisione.
    static func splitFrames(
        left: NSRect,
        right: NSRect,
        splitX: CGFloat,
        minimumWidth: CGFloat = 200
    ) -> (left: NSRect, right: NSRect)? {
        guard right.maxX - left.minX > minimumWidth * 2 else { return nil }
        let x = min(max(splitX, left.minX + minimumWidth), right.maxX - minimumWidth)
        return (
            NSRect(x: left.minX, y: left.minY, width: x - left.minX, height: left.height),
            NSRect(x: x, y: right.minY, width: right.maxX - x, height: right.height)
        )
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
