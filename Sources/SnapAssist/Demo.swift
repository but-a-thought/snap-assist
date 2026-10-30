import AppKit

/// Modalità nascosta `--demo`: mostra il pannello sulla metà destra dello
/// schermo con le finestre reali (senza miniature) e chiude dopo pochi secondi.
/// Serve per controllare l'aspetto del pannello senza dover agganciare nulla.
enum Demo {
    private static let controller = PickerController()
    private static var dividerPanel: DividerPanel?

    /// Sposta la finestra in primo piano a metà sinistra per 5 secondi, utile
    /// per verificare a mano che il pannello compaia. Richiede Accessibilità.
    static func runSnap() {
        guard let screen = NSScreen.screens.first,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = AX.focusedWindow(pid: app.processIdentifier),
              let original = AX.frame(window) else {
            print("Nessuna finestra da spostare")
            return
        }

        let base = screen.visibleFrame
        let target = ScreenGeometry.accessibility(fromAppKit: NSRect(
            x: base.minX,
            y: base.minY,
            width: base.width / 2,
            height: base.height
        ))

        AX.setFrame(window, target)
        print("Finestra agganciata a sinistra per 5 secondi…")
        fflush(stdout)
        Thread.sleep(forTimeInterval: 5)
        AX.setFrame(window, original)
        print("Ripristinata")
    }

    static func runDivider() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let base = screen.visibleFrame
        let frame = NSRect(x: base.midX - 6, y: base.minY, width: 12, height: base.height)

        let panel = DividerPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = DividerView(frame: NSRect(origin: .zero, size: frame.size))
        view.previewHighlight = ProcessInfo.processInfo.environment["AFFIANCA_DIVIDER_GRIP"] == "1"
        panel.contentView = view
        panel.orderFrontRegardless()
        dividerPanel = panel

        let rect = ScreenGeometry.accessibility(fromAppKit: frame)
        print("RECT \(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))")
        fflush(stdout)

        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            NSApp.terminate(nil)
        }
    }

    static func run() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let base = screen.visibleFrame
        let snapped = NSRect(x: base.minX, y: base.minY, width: base.width / 2, height: base.height)
        let target = NSRect(x: base.midX, y: base.minY, width: base.width / 2, height: base.height)

        let event = SnapEvent(
            pid: 0,
            windowID: nil,
            window: AXUIElementCreateSystemWide(),
            frame: snapped,
            zone: .leftHalf,
            screen: screen,
            target: target
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let thumbnails = ProcessInfo.processInfo.environment["AFFIANCA_DEMO_THUMBS"] == "1"
            _ = controller.present(for: event, thumbnails: thumbnails)
            let rect = ScreenGeometry.accessibility(fromAppKit: target)
            print("RECT \(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))")
            fflush(stdout)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            controller.dismiss(silently: true)
            NSApp.terminate(nil)
        }
    }
}
