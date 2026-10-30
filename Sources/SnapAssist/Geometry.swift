import AppKit

enum SnapSide: String {
    case left
    case right
}

struct SnapEvent {
    let pid: pid_t
    let window: AXUIElement
    let frame: NSRect
    let side: SnapSide
    let screen: NSScreen
    /// Metà opposta su cui finirà la finestra scelta (coordinate AppKit).
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
        let side: SnapSide
        let screen: NSScreen
        /// Area di riferimento usata per il calcolo (visibleFrame o frame).
        let base: NSRect
    }

    /// Riconosce una finestra occupata esattamente su metà orizzontale dello
    /// schermo, con una tolleranza per menu bar, Dock e piccoli arrotondamenti.
    static func detect(_ rect: NSRect) -> Hit? {
        for screen in NSScreen.screens {
            for base in [screen.visibleFrame, screen.frame] {
                guard base.width > 300, base.height > 300 else { continue }

                // Tolleranze volutamente non strettissime: coprono menu bar,
                // Dock e il "gap" tra finestre configurabile in Rectangle.
                let halfWidth = base.width / 2
                guard abs(rect.width - halfWidth) <= max(28, halfWidth * 0.08) else { continue }
                guard abs(rect.height - base.height) <= max(40, base.height * 0.09) else { continue }
                guard abs(rect.minY - base.minY) <= max(40, base.height * 0.09) else { continue }

                if abs(rect.minX - base.minX) <= 28 {
                    return Hit(side: .left, screen: screen, base: base)
                }
                if abs(rect.maxX - base.maxX) <= 28 {
                    return Hit(side: .right, screen: screen, base: base)
                }
            }
        }
        return nil
    }

    /// Metà opposta a quella occupata, alla stessa altezza della finestra agganciata.
    static func oppositeHalf(of rect: NSRect, side: SnapSide, base: NSRect) -> NSRect {
        let halfWidth = base.width / 2
        let x = side == .left ? base.minX + halfWidth : base.minX
        return NSRect(x: x, y: rect.minY, width: halfWidth, height: rect.height)
    }
}
