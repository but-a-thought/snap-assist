import AppKit

/// Autodiagnosi della geometria, eseguibile con `SnapAssist --check`.
/// Non richiede permessi e non apre finestre.
enum SelfCheck {
    static func run() -> Int32 {
        var failures = 0

        func check(_ condition: Bool, _ label: String) {
            print(condition ? "✓ \(label)" : "✗ \(label)")
            if !condition { failures += 1 }
        }

        let screens = NSScreen.screens
        print("Accessibilità: \(AX.isTrusted ? "consentita" : "non consentita")")
        print("Mission Control/Launchpad attivo: \(WindowList.isSystemOverlayActive() ? "sì" : "no")")
        check(!screens.isEmpty, "almeno uno schermo rilevato")

        for screen in screens {
            let base = screen.visibleFrame
            let left = NSRect(x: base.minX, y: base.minY, width: base.width / 2, height: base.height)
            let right = NSRect(x: base.midX, y: base.minY, width: base.width / 2, height: base.height)
            let centered = base.insetBy(dx: base.width * 0.1, dy: base.height * 0.1)

            check(SnapDetector.detect(left)?.side == .left, "metà sinistra riconosciuta (\(screen.localizedName))")
            check(SnapDetector.detect(right)?.side == .right, "metà destra riconosciuta (\(screen.localizedName))")
            check(SnapDetector.detect(centered) == nil, "finestra centrale ignorata (\(screen.localizedName))")
            check(SnapDetector.detect(screen.frame) == nil, "schermo intero ignorato (\(screen.localizedName))")

            let roundTrip = ScreenGeometry.appKit(fromAccessibility: ScreenGeometry.accessibility(fromAppKit: left))
            check(
                abs(roundTrip.minX - left.minX) < 0.5
                    && abs(roundTrip.minY - left.minY) < 0.5
                    && abs(roundTrip.width - left.width) < 0.5
                    && abs(roundTrip.height - left.height) < 0.5,
                "conversione coordinate stabile (\(screen.localizedName))"
            )

            let target = SnapDetector.oppositeHalf(of: left, side: .left, base: base)
            check(
                abs(target.minX - base.midX) < 0.5
                    && abs(target.width - base.width / 2) < 0.5
                    && abs(target.height - left.height) < 0.5,
                "metà opposta calcolata (\(screen.localizedName))"
            )
        }

        let visibleWindows = WindowList.candidates(excludingFrame: nil)
        print("Finestre visibili rilevate: \(visibleWindows.count)")
        for window in visibleWindows.prefix(4) {
            let title = window.title.isEmpty ? window.appName : "\(window.appName) · \(window.title)"
            print("  • \(title)")
        }

        print(failures == 0 ? "OK" : "\(failures) controlli falliti")
        return failures == 0 ? 0 : 1
    }
}
