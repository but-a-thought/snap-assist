import AppKit

/// Test funzionali eseguibili con `SnapAssist --test`.
/// Non richiedono il pannello di scelta: usano finestre reali e simulate.
enum FunctionalTests {
    private static var passed = 0
    private static var failed = 0
    private static var skipped = 0
    private static var failures: [String] = []
    private static var currentGroup = ""

    static func run() -> Int32 {
        print("Snap Assist — test funzionali")
        print("")

        geometry()
        windowList()
        systemOverlay()
        layouts()
        picker()
        divider()
        accessibility()

        print("")
        print("────────────────────────────────")
        print("Passati: \(passed)   Falliti: \(failed)   Saltati: \(skipped)")

        if !failures.isEmpty {
            print("")
            print("Falliti:")
            for failure in failures {
                print("  ✗ \(failure)")
            }
        }

        return failed == 0 ? 0 : 1
    }

    // MARK: - Utilità

    private static func group(_ name: String) {
        currentGroup = name
        print("▸ \(name)")
    }

    @discardableResult
    private static func expect(_ condition: Bool, _ name: String) -> Bool {
        if condition {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            failures.append("\(currentGroup) → \(name)")
            print("  ✗ \(name)")
        }
        return condition
    }

    private static func skip(_ name: String) {
        skipped += 1
        print("  – \(name) (saltato)")
    }

    private static func pump(_ seconds: TimeInterval = 0.25) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - Geometria

    private static func geometry() {
        group("Geometria e rilevamento")

        guard let screen = NSScreen.screens.first else {
            expect(false, "schermo disponibile")
            return
        }

        let base = screen.visibleFrame
        let halfWidth = base.width / 2
        let left = NSRect(x: base.minX, y: base.minY, width: halfWidth, height: base.height)
        let right = NSRect(x: base.midX, y: base.minY, width: halfWidth, height: base.height)

        expect(SnapDetector.detect(left)?.zone == .leftHalf, "metà sinistra riconosciuta")
        expect(SnapDetector.detect(right)?.zone == .rightHalf, "metà destra riconosciuta")

        let fullLeft = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width / 2, height: screen.frame.height)
        let fullRight = NSRect(x: screen.frame.midX, y: screen.frame.minY, width: screen.frame.width / 2, height: screen.frame.height)
        expect(SnapDetector.detect(fullLeft)?.zone == .leftHalf, "metà sinistra a schermo intero riconosciuta")
        expect(SnapDetector.detect(fullRight)?.zone == .rightHalf, "metà destra a schermo intero riconosciuta")

        expect(SnapDetector.detect(base.insetBy(dx: base.width * 0.15, dy: base.height * 0.1)) == nil, "finestra centrata ignorata")
        expect(SnapDetector.detect(screen.frame) == nil, "schermo intero ignorato")
        expect(SnapDetector.detect(.zero) == nil, "rettangolo nullo ignorato")

        let shortHalf = NSRect(x: base.minX, y: base.minY, width: halfWidth, height: base.height * 0.6)
        expect(SnapDetector.detect(shortHalf) == nil, "mezza larghezza ma altezza ridotta ignorata")

        let gapLeft = NSRect(x: base.minX + 20, y: base.minY, width: halfWidth - 20, height: base.height)
        let gapRight = NSRect(x: base.midX, y: base.minY, width: halfWidth - 20, height: base.height)
        expect(SnapDetector.detect(gapLeft)?.zone == .leftHalf, "snap sinistro con gap riconosciuto")
        expect(SnapDetector.detect(gapRight)?.zone == .rightHalf, "snap destro con gap riconosciuto")

        let wide = NSRect(x: base.minX, y: base.minY, width: base.width * 0.6, height: base.height)
        expect(SnapDetector.detect(wide) == nil, "larghezza 60% ignorata")

        let nearHalf = NSRect(x: base.minX, y: base.minY, width: base.width * 0.47, height: base.height)
        expect(SnapDetector.detect(nearHalf)?.zone == .leftHalf, "larghezza 47% riconosciuta")

        let roundTrip = ScreenGeometry.appKit(fromAccessibility: ScreenGeometry.accessibility(fromAppKit: left))
        expect(
            abs(roundTrip.minX - left.minX) < 0.5
                && abs(roundTrip.minY - left.minY) < 0.5
                && abs(roundTrip.width - left.width) < 0.5
                && abs(roundTrip.height - left.height) < 0.5,
            "conversione coordinate stabile"
        )

        let targetLeft = SnapDetector.oppositeHalf(of: left, zone: .leftHalf, base: base)
        expect(abs(targetLeft.minX - base.midX) < 0.5 && abs(targetLeft.width - halfWidth) < 0.5, "metà opposta da sinistra")

        let targetRight = SnapDetector.oppositeHalf(of: right, zone: .rightHalf, base: base)
        expect(abs(targetRight.minX - base.minX) < 0.5 && abs(targetRight.width - halfWidth) < 0.5, "metà opposta da destra")

        let offset = NSRect(x: base.minX, y: base.minY + 30, width: halfWidth, height: base.height - 30)
        let targetOffset = SnapDetector.oppositeHalf(of: offset, zone: .leftHalf, base: base)
        expect(abs(targetOffset.minY - offset.minY) < 0.5 && abs(targetOffset.height - offset.height) < 0.5, "metà opposta mantiene l'offset verticale")

        let quarterWidth = base.width / 2
        let quarterHeight = base.height / 2
        let topLeft = NSRect(x: base.minX, y: base.midY, width: quarterWidth, height: quarterHeight)
        let topRight = NSRect(x: base.midX, y: base.midY, width: quarterWidth, height: quarterHeight)
        let bottomLeft = NSRect(x: base.minX, y: base.minY, width: quarterWidth, height: quarterHeight)
        let bottomRight = NSRect(x: base.midX, y: base.minY, width: quarterWidth, height: quarterHeight)

        expect(SnapDetector.detect(topLeft)?.zone == .topLeft, "quarto in alto a sinistra riconosciuto")
        expect(SnapDetector.detect(topRight)?.zone == .topRight, "quarto in alto a destra riconosciuto")
        expect(SnapDetector.detect(bottomLeft)?.zone == .bottomLeft, "quarto in basso a sinistra riconosciuto")
        expect(SnapDetector.detect(bottomRight)?.zone == .bottomRight, "quarto in basso a destra riconosciuto")

        let quarters = SnapDetector.quarterRects(in: base)
        expect(quarters.count == 4, "quattro quarti calcolati")
        expect(abs((quarters[.topLeft]?.width ?? 0) - quarterWidth) < 1, "larghezza quarto corretta")

        let freeTarget = SnapDetector.target(for: .topLeft, rect: topLeft, base: base) { _ in false }
        expect(abs(freeTarget.minX - base.midX) < 1 && abs(freeTarget.minY - base.midY) < 1, "primo quarto libero scelto a destra")

        let occupiedTarget = SnapDetector.target(for: .topLeft, rect: topLeft, base: base) { candidate in
            abs(candidate.minX - topRight.minX) < 1 && abs(candidate.minY - topRight.minY) < 1
        }
        expect(abs(occupiedTarget.minX - base.minX) < 1 && abs(occupiedTarget.minY - base.minY) < 1, "se il quarto adiacente è occupato passa a quello sotto")

        if NSScreen.screens.count > 1 {
            let other = NSScreen.screens[1]
            let otherBase = other.visibleFrame
            let otherLeft = NSRect(x: otherBase.minX, y: otherBase.minY, width: otherBase.width / 2, height: otherBase.height)
            expect(SnapDetector.detect(otherLeft)?.zone == .leftHalf, "secondo schermo: metà sinistra riconosciuta")
        } else {
            skip("secondo schermo non collegato")
        }
    }

    // MARK: - Finestre

    private static func windowList() {
        group("Elenco finestre")
        let windows = WindowList.allVisibleWindows()

        guard expect(!windows.isEmpty, "finestre visibili trovate") else {
            skip("test successivi sulle finestre")
            return
        }

        expect(windows.allSatisfy { $0.frame.width >= 180 && $0.frame.height >= 120 }, "dimensioni minime rispettate")

        let myPid = ProcessInfo.processInfo.processIdentifier
        expect(windows.allSatisfy { $0.pid != myPid }, "finestre dell'app escluse")
        expect(Set(windows.map { $0.id }).count == windows.count, "nessun ID duplicato")

        let candidates = WindowList.candidates(excludingFrame: nil)
        expect(!candidates.isEmpty, "candidati per il pannello trovati")
        expect(candidates.allSatisfy { $0.pid != myPid }, "candidati senza l'app stessa")

        if let first = windows.first {
            let filtered = WindowList.candidates(excludingFrame: first.frame)
            let stillPresent = filtered.contains { window in
                abs(window.frame.minX - first.frame.minX)
                    + abs(window.frame.minY - first.frame.minY)
                    + abs(window.frame.width - first.frame.width)
                    + abs(window.frame.height - first.frame.height) < 40
            }
            expect(!stillPresent, "la finestra agganciata è esclusa")

            expect(
                !WindowList.isExcluded(
                    id: 2,
                    frame: first.frame,
                    excludingID: 1,
                    excludingFrame: nil
                ),
                "un'altra finestra sullo stesso frame non è esclusa"
            )
            expect(
                WindowList.isExcluded(
                    id: 1,
                    frame: first.frame,
                    excludingID: 1,
                    excludingFrame: nil
                ),
                "la finestra agganciata è esclusa per ID"
            )
            expect(
                WindowList.isExcluded(
                    id: 2,
                    frame: first.frame,
                    excludingID: nil,
                    excludingFrame: first.frame
                ),
                "fallback per frame quando l'ID non è disponibile"
            )
        }

        expect(WindowList.candidates(excludingFrame: nil, limit: 2).count <= 2, "limite candidati rispettato")

        if let first = windows.first {
            expect(WindowList.isOccupied(first.frame), "area occupata riconosciuta")
        }
        expect(!WindowList.isOccupied(CGRect(x: 100_000, y: 100_000, width: 500, height: 500)), "area fuori schermo non occupata")
    }

    // MARK: - Mission Control

    private static func systemOverlay() {
        group("Mission Control / Launchpad")

        guard let screen = NSScreen.screens.first else { return }
        let full = screen.frame
        let dockBar = NSRect(x: full.midX - 300, y: full.minY + 6, width: 600, height: 60)

        func window(_ rect: NSRect, layer: Int, pid: pid_t) -> SystemWindow {
            SystemWindow(pid: pid, layer: layer, frame: rect)
        }

        expect(
            WindowList.isSystemOverlay(windows: [window(full, layer: 20, pid: 777)], dockPid: 777, screens: [screen]),
            "overlay di Mission Control riconosciuto"
        )
        expect(
            !WindowList.isSystemOverlay(windows: [window(dockBar, layer: 20, pid: 777)], dockPid: 777, screens: [screen]),
            "barra del Dock non scambiata per overlay"
        )
        expect(
            !WindowList.isSystemOverlay(windows: [window(full, layer: 20, pid: 888)], dockPid: 777, screens: [screen]),
            "finestra a tutto schermo di un'altra app ignorata"
        )
        expect(
            !WindowList.isSystemOverlay(windows: [window(full, layer: 0, pid: 777)], dockPid: 777, screens: [screen]),
            "finestra normale di layer 0 ignorata"
        )
        expect(
            !WindowList.isSystemOverlay(windows: [], dockPid: 777, screens: [screen]),
            "nessuna finestra, nessun overlay"
        )
    }

    // MARK: - Pannello

    private static func layouts() {
        group("Layout e zone")

        guard let screen = NSScreen.screens.first else { return }
        let halves = ZoneLayout.presets[0]

        let rects = halves.rects(in: screen)
        let base = screen.visibleFrame
        expect(rects.count == 2, "layout a due colonne ha due zone")
        if rects.count == 2 {
            expect(abs(rects[0].minX - base.minX) < 1 && abs(rects[0].maxX - base.midX) < 1, "prima zona = metà sinistra")
            expect(abs(rects[1].minX - base.midX) < 1 && abs(rects[1].maxX - base.maxX) < 1, "seconda zona = metà destra")
        }

        expect(halves.zoneIndex(at: NSPoint(x: base.minX + 20, y: base.midY), in: screen) == 0, "hit test sulla zona sinistra")
        expect(halves.zoneIndex(at: NSPoint(x: base.maxX - 20, y: base.midY), in: screen) == 1, "hit test sulla zona destra")

        let grid = ZoneLayout.grid(columns: 2, rows: 3)
        expect(grid.zones.count == 6, "griglia 2×3 ha sei zone")
        let area = grid.zones.reduce(CGFloat.zero) { $0 + $1.width * $1.height }
        expect(abs(area - 1) < 0.0001, "le zone coprono tutta l'area")
        expect(grid.zones.allSatisfy { $0.minX >= 0 && $0.maxX <= 1 && $0.minY >= 0 && $0.maxY <= 1 }, "zone dentro i limiti normalizzati")

        expect(ZoneLayout.presets.allSatisfy { !$0.zones.isEmpty }, "tutti i preset hanno zone")
        expect(ZoneLayout.presets.count >= 6, "almeno sei preset disponibili")

        let data = try? JSONEncoder().encode(halves)
        let decoded = data.flatMap { try? JSONDecoder().decode(ZoneLayout.self, from: $0) }
        expect(decoded == halves, "layout serializzabile e rileggibile")

        let mainStack = ZoneLayout.presets.first { $0.name == "Main + stack" }
        expect(mainStack?.zones.count == 3, "preset main + stack ha tre zone")
        if let mainStack {
            let mapped = mainStack.rects(in: screen)
            expect(abs(mapped[0].width - base.width * 2 / 3) < 1, "zona principale larga due terzi")
        }

        let custom = ZoneLayout.custom(columns: [0.25, 0.75], rows: [0.4, 0.6])
        expect(custom.zones.count == 4, "griglia custom ha quattro celle")
        expect(abs(custom.zones[1].width - 0.75) < 0.001, "larghezza colonna personalizzata")
        expect(abs(custom.zones[2].height - 0.6) < 0.001, "altezza riga personalizzata")

        let components = custom.gridComponents()
        expect(components != nil, "griglia custom ricostruibile")
        if let components {
            expect(abs(components.columns[0] - 0.25) < 0.001, "colonne ricostruite")
            expect(abs(components.rows[1] - 0.6) < 0.001, "righe ricostruite")
        }

        if let mainStack {
            expect(mainStack.gridComponents() == nil, "layout asimmetrico non è una griglia")
        }

        let centerSides = ZoneLayout.presets.first { $0.name == "Center + sides" }
        expect(centerSides?.zones.count == 3, "preset centro + lati ha tre zone")
        if let centerSides {
            let mapped = centerSides.rects(in: screen)
            expect(abs(mapped[1].width - base.width * 0.6) < 1, "zona centrale larga il 60%")
            expect(abs(mapped[0].width - base.width * 0.2) < 1, "zona laterale larga il 20%")
        }

        let free = ZoneLayout(name: "Free", zones: [
            CGRect(x: 0, y: 0, width: 0.5, height: 0.7),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        ])
        expect(free.zones.count == 2, "layout libero accetta zone arbitrarie")
        expect(free.zoneIndex(at: NSPoint(x: base.minX + 10, y: base.maxY - 10), in: screen) == 0, "hit test su zona libera in alto a sinistra")
        expect(free.zoneIndex(at: NSPoint(x: base.maxX - 10, y: base.minY + 10), in: screen) == 1, "hit test su zona libera in basso a destra")
    }

    private static func picker() {
        group("Pannello di scelta")

        guard let screen = NSScreen.screens.first else { return }
        let base = screen.visibleFrame
        let snapped = NSRect(x: base.minX, y: base.minY, width: base.width / 2, height: base.height)
        let target = NSRect(x: base.midX, y: base.minY, width: base.width / 2, height: base.height)

        let items = (0..<5).map { index in
            WindowCandidate(
                id: CGWindowID(index + 1),
                pid: pid_t(1000 + index),
                appName: "App \(index)",
                title: "Finestra \(index)",
                frame: .zero,
                icon: nil
            )
        }
        let view = PickerView(frame: NSRect(x: 0, y: 0, width: 900, height: 900), items: items, note: "test")
        view.layoutSubtreeIfNeeded()
        let cards = view.subviews.compactMap { $0 as? CardView }

        expect(cards.count == items.count, "una scheda per ogni finestra")
        expect(cards.allSatisfy { $0.frame.width > 100 && $0.frame.height > 80 }, "schede con dimensioni sensate")
        expect(cards.allSatisfy { view.bounds.contains($0.frame) }, "schede dentro il pannello")

        let controller = PickerController()
        let event = SnapEvent(
            pid: 0,
            windowID: nil,
            window: AXUIElementCreateSystemWide(),
            frame: snapped,
            zone: .leftHalf,
            screen: screen,
            target: target
        )
        let shown = controller.present(for: event, thumbnails: false)
        guard expect(shown, "pannello mostrato") else { return }
        pump(0.4)

        let visiblePanels = NSApp.windows.filter { $0.level == .statusBar && $0.isVisible }
        expect(visiblePanels.count == 1, "un solo pannello visibile")

        if let panel = visiblePanels.first {
            expect(
                abs(panel.frame.minX - target.minX) < 2
                    && abs(panel.frame.width - target.width) < 2
                    && abs(panel.frame.minY - target.minY) < 2,
                "pannello nella metà opposta"
            )
            expect(panel.styleMask.contains(.nonactivatingPanel), "pannello non attivante")
        }

        controller.dismiss()
        pump(0.5)
        expect(!NSApp.windows.contains { $0.level == .statusBar && $0.isVisible }, "pannello chiuso dopo l'annullamento")
    }

    // MARK: - Barra

    private static func divider() {
        group("Barra tra finestre")

        guard let screen = NSScreen.screens.first else { return }
        let base = screen.visibleFrame
        let left = NSRect(x: base.minX, y: base.minY, width: base.width / 2, height: base.height)
        let right = NSRect(x: base.midX, y: base.minY, width: base.width / 2, height: base.height)

        func placed(_ rect: NSRect, id: CGWindowID, pid: pid_t) -> DividerGeometry.PlacedWindow {
            DividerGeometry.PlacedWindow(id: id, pid: pid, rect: rect)
        }

        let leftWindow = placed(left, id: 11, pid: 1001)
        let rightWindow = placed(right, id: 12, pid: 1002)
        let pairs = DividerGeometry.detectPairs(windows: [leftWindow, rightWindow], screens: [screen])
        let pair = pairs.first

        expect(pair != nil, "coppia affiancata rilevata")
        if let pair {
            expect(pair.orientation == .vertical, "coppia orizzontale usa barra verticale")

            let rect = DividerGeometry.dividerRect(for: pair)
            expect(abs(rect.midX - base.midX) < 1, "barra al centro esatto")
            expect(abs(rect.height - base.height) < 1, "barra alta come le finestre")
            expect(abs(rect.width - 12) < 0.5, "larghezza barra corretta")

            let nearPointer = NSPoint(x: base.midX + 10, y: base.midY)
            expect(
                DividerGeometry.shouldReveal(pair: pair, mouse: nearPointer),
                "barra visibile col puntatore vicino"
            )
            let farPointer = NSPoint(x: base.midX + 200, y: base.midY)
            expect(
                !DividerGeometry.shouldReveal(pair: pair, mouse: farPointer),
                "barra nascosta col puntatore lontano"
            )

            let fullCover = placed(base, id: 1, pid: 900)
            expect(
                DividerGeometry.isCovered(pair: pair, windows: [fullCover, leftWindow, rightWindow]),
                "barra coperta da una finestra davanti"
            )
            expect(
                !DividerGeometry.isCovered(pair: pair, windows: [leftWindow, rightWindow, fullCover]),
                "finestra dietro alla coppia non copre la barra"
            )
            let smallWindow = placed(
                NSRect(x: base.minX + 40, y: base.maxY - 90, width: 120, height: 60),
                id: 2,
                pid: 901
            )
            expect(
                !DividerGeometry.isCovered(pair: pair, windows: [smallWindow, leftWindow, rightWindow]),
                "finestra davanti ma lontana dal confine non copre la barra"
            )

            let frames = DividerGeometry.splitFrames(for: pair, at: base.minX + base.width * 0.7)
            expect(frames != nil, "calcolo della divisione disponibile")
            if let frames {
                expect(abs(frames.first.maxX - frames.second.minX) < 0.5, "divisione senza buchi")
                expect(abs(frames.first.width + frames.second.width - base.width) < 0.5, "larghezze sommate al totale")
            }
            let clampedLow = DividerGeometry.splitFrames(for: pair, at: base.minX + 10)
            expect(clampedLow != nil && clampedLow!.first.width >= 120, "larghezza minima a sinistra")
            let clampedHigh = DividerGeometry.splitFrames(for: pair, at: base.maxX - 10)
            expect(clampedHigh != nil && clampedHigh!.second.width >= 120, "larghezza minima a destra")
        }

        let gap = 10.0
        let withGap = [
            placed(NSRect(x: base.minX + gap / 2, y: base.minY, width: base.width / 2 - gap / 2, height: base.height), id: 21, pid: 2001),
            placed(NSRect(x: base.midX + gap / 2, y: base.minY, width: base.width / 2 - gap / 2, height: base.height), id: 22, pid: 2002)
        ]
        expect(DividerGeometry.detectPairs(windows: withGap, screens: [screen]).count == 1, "coppia con gap rilevata")

        let split = [
            placed(NSRect(x: base.minX, y: base.minY, width: base.width * 0.6, height: base.height), id: 31, pid: 3001),
            placed(NSRect(x: base.minX + base.width * 0.6, y: base.minY, width: base.width * 0.4, height: base.height), id: 32, pid: 3002)
        ]
        expect(DividerGeometry.detectPairs(windows: split, screens: [screen]).count == 1, "coppia 60/40 rilevata")

        let differentHeights = [
            placed(left, id: 41, pid: 4001),
            placed(NSRect(x: base.midX, y: base.minY, width: base.width / 2, height: base.height * 0.6), id: 42, pid: 4002)
        ]
        expect(DividerGeometry.detectPairs(windows: differentHeights, screens: [screen]).isEmpty, "altezze diverse ignorate")

        expect(
            DividerGeometry.detectPairs(windows: [placed(left, id: 51, pid: 5001)], screens: [screen]).isEmpty,
            "finestra singola ignorata"
        )

        let sameSide = [
            placed(left, id: 61, pid: 6001),
            placed(NSRect(x: base.minX + 40, y: base.minY, width: base.width / 2, height: base.height), id: 62, pid: 6002)
        ]
        expect(DividerGeometry.detectPairs(windows: sameSide, screens: [screen]).isEmpty, "due finestre sullo stesso lato ignorate")

        // Finestre impilate: barra orizzontale.
        let top = NSRect(x: base.minX, y: base.midY, width: base.width, height: base.height / 2)
        let bottom = NSRect(x: base.minX, y: base.minY, width: base.width, height: base.height / 2)
        let stacked = [
            placed(top, id: 71, pid: 7001),
            placed(bottom, id: 72, pid: 7002)
        ]
        let horizontalPairs = DividerGeometry.detectPairs(windows: stacked, screens: [screen])
        expect(horizontalPairs.first?.orientation == .horizontal, "finestre impilate usano barra orizzontale")
        if let horizontal = horizontalPairs.first {
            let rect = DividerGeometry.dividerRect(for: horizontal)
            expect(abs(rect.midY - base.midY) < 1, "barra orizzontale al centro")
            expect(abs(rect.width - base.width) < 1, "barra orizzontale larga come le finestre")

            let frames = DividerGeometry.splitFrames(for: horizontal, at: base.midY - 40)
            expect(frames != nil, "divisione verticale calcolata")
            if let frames {
                expect(abs(frames.first.height + frames.second.height - base.height) < 0.5, "altezze sommate al totale")
            }
        }

        // Quattro quarti: due barre verticali e due orizzontali.
        let quarterWidth = base.width / 2
        let quarterHeight = base.height / 2
        let quarters = [
            placed(NSRect(x: base.minX, y: base.midY, width: quarterWidth, height: quarterHeight), id: 81, pid: 8001),
            placed(NSRect(x: base.midX, y: base.midY, width: quarterWidth, height: quarterHeight), id: 82, pid: 8002),
            placed(NSRect(x: base.minX, y: base.minY, width: quarterWidth, height: quarterHeight), id: 83, pid: 8003),
            placed(NSRect(x: base.midX, y: base.minY, width: quarterWidth, height: quarterHeight), id: 84, pid: 8004)
        ]
        let quarterPairs = DividerGeometry.detectPairs(windows: quarters, screens: [screen])
        expect(quarterPairs.count == 4, "quattro quarti producono quattro barre")
        expect(quarterPairs.contains { $0.orientation == .vertical }, "barre verticali tra quarti affiancati")
        expect(quarterPairs.contains { $0.orientation == .horizontal }, "barre orizzontali tra quarti impilati")
    }

    // MARK: - Accessibilità

    private static func accessibility() {
        group("Accessibilità (integrazione reale)")

        guard AX.isTrusted else {
            skip("permesso Accessibilità non concesso")
            skip("lettura finestra in primo piano")
            skip("spostamento e ripristino finestra")
            return
        }
        expect(true, "permesso Accessibilità concesso")

        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = AX.focusedWindow(pid: app.processIdentifier),
              let frame = AX.frame(window) else {
            skip("lettura finestra in primo piano")
            skip("spostamento e ripristino finestra")
            return
        }

        expect(frame.width > 0 && frame.height > 0, "frame della finestra in primo piano")
        expect(AX.window(pid: app.processIdentifier, matching: frame) != nil, "finestra ritrovata per frame")

        guard let screen = NSScreen.screens.first else { return }
        let base = screen.visibleFrame
        let target = ScreenGeometry.accessibility(fromAppKit: NSRect(
            x: base.minX,
            y: base.minY,
            width: base.width / 2,
            height: base.height
        ))

        AX.setFrame(window, target)
        pump(0.25)
        let moved = AX.frame(window) ?? .zero
        expect(abs(moved.minX - target.minX) < 60 && abs(moved.width - target.width) < 80, "finestra spostata a metà sinistra")

        AX.setFrame(window, frame)
        pump(0.25)
        let restored = AX.frame(window) ?? .zero
        expect(abs(restored.minX - frame.minX) < 60 && abs(restored.width - frame.width) < 80, "finestra ripristinata")
    }
}

final class TestRunner: NSObject, NSApplicationDelegate {
    var exitCode: Int32 = 1

    func applicationDidFinishLaunching(_ notification: Notification) {
        exitCode = FunctionalTests.run()
        fflush(stdout)
        exit(exitCode)
    }
}
