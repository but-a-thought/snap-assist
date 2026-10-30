import AppKit

enum SnapZone: String, CaseIterable {
    case leftHalf
    case rightHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var isHalf: Bool {
        self == .leftHalf || self == .rightHalf
    }

    /// Quarti da provare per riempire lo schermo, in ordine di preferenza.
    var adjacentQuarters: [SnapZone] {
        switch self {
        case .topLeft: return [.topRight, .bottomLeft, .bottomRight]
        case .topRight: return [.topLeft, .bottomRight, .bottomLeft]
        case .bottomLeft: return [.bottomRight, .topLeft, .topRight]
        case .bottomRight: return [.bottomLeft, .topRight, .topLeft]
        case .leftHalf, .rightHalf: return []
        }
    }
}

struct SnapEvent {
    let pid: pid_t
    let windowID: CGWindowID?
    let window: AXUIElement
    let frame: NSRect
    let zone: SnapZone
    let screen: NSScreen
    /// Area su cui mostrare il pannello e in cui finirà la finestra scelta.
    let target: NSRect
}

enum ScreenGeometry {
    /// AppKit misura la Y dal basso dello schermo principale, Accessibility
    /// dall'alto. Teniamo qui l'unica conversione del progetto.
    private static var mainScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func appKit(fromAccessibility rect: CGRect) -> NSRect {
        let height = mainScreenHeight
        return NSRect(x: rect.origin.x, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    static func accessibility(fromAppKit rect: NSRect) -> CGRect {
        let height = mainScreenHeight
        return CGRect(x: rect.origin.x, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}

enum SnapDetector {
    struct Hit {
        let zone: SnapZone
        let screen: NSScreen
        /// Area di riferimento usata per il calcolo (visibleFrame o frame).
        let base: NSRect
    }

    /// Riconosce metà e quarti dello schermo, con tolleranze per menu bar,
    /// Dock, gap di Rectangle e piccoli arrotondamenti.
    static func detect(_ rect: NSRect) -> Hit? {
        for screen in NSScreen.screens {
            for base in [screen.visibleFrame, screen.frame] {
                guard base.width > 300, base.height > 300 else { continue }

                let halfWidth = base.width / 2
                let halfHeight = base.height / 2
                let widthTolerance = max(24, halfWidth * 0.08)
                let heightTolerance = max(30, base.height * 0.09)
                let quarterTolerance = max(30, halfHeight * 0.09)

                // Metà a tutta altezza.
                if abs(rect.width - halfWidth) <= widthTolerance,
                   abs(rect.height - base.height) <= heightTolerance,
                   abs(rect.minY - base.minY) <= max(30, base.height * 0.08) {
                    if abs(rect.minX - base.minX) <= 28 {
                        return Hit(zone: .leftHalf, screen: screen, base: base)
                    }
                    if abs(rect.maxX - base.maxX) <= 28 {
                        return Hit(zone: .rightHalf, screen: screen, base: base)
                    }
                }

                // Quarti.
                guard abs(rect.width - halfWidth) <= widthTolerance,
                      abs(rect.height - halfHeight) <= quarterTolerance else { continue }

                if abs(rect.minX - base.minX) <= 28 {
                    if abs(rect.minY - base.midY) <= quarterTolerance {
                        return Hit(zone: .topLeft, screen: screen, base: base)
                    }
                    if abs(rect.minY - base.minY) <= quarterTolerance {
                        return Hit(zone: .bottomLeft, screen: screen, base: base)
                    }
                }
                if abs(rect.maxX - base.maxX) <= 28 {
                    if abs(rect.minY - base.midY) <= quarterTolerance {
                        return Hit(zone: .topRight, screen: screen, base: base)
                    }
                    if abs(rect.minY - base.minY) <= quarterTolerance {
                        return Hit(zone: .bottomRight, screen: screen, base: base)
                    }
                }
            }
        }
        return nil
    }

    /// Metà opposta a quella occupata, alla stessa altezza della finestra.
    static func oppositeHalf(of rect: NSRect, zone: SnapZone, base: NSRect) -> NSRect {
        let halfWidth = base.width / 2
        let x = zone == .leftHalf ? base.minX + halfWidth : base.minX
        return NSRect(x: x, y: rect.minY, width: halfWidth, height: rect.height)
    }

    static func quarterRects(in base: NSRect) -> [SnapZone: NSRect] {
        let width = base.width / 2
        let height = base.height / 2
        return [
            .topLeft: NSRect(x: base.minX, y: base.midY, width: width, height: height),
            .topRight: NSRect(x: base.midX, y: base.midY, width: width, height: height),
            .bottomLeft: NSRect(x: base.minX, y: base.minY, width: width, height: height),
            .bottomRight: NSRect(x: base.midX, y: base.minY, width: width, height: height)
        ]
    }

    /// Zona in cui mettere la finestra scelta: la metà opposta, oppure il
    /// primo quarto libero adiacente.
    static func target(
        for zone: SnapZone,
        rect: NSRect,
        base: NSRect,
        isOccupied: (NSRect) -> Bool
    ) -> NSRect {
        if zone.isHalf {
            return oppositeHalf(of: rect, zone: zone, base: base)
        }

        let quarters = quarterRects(in: base)
        for candidate in zone.adjacentQuarters {
            guard let candidateRect = quarters[candidate] else { continue }
            if !isOccupied(candidateRect) { return candidateRect }
        }
        if let first = zone.adjacentQuarters.first, let fallback = quarters[first] {
            return fallback
        }
        return rect
    }
}
