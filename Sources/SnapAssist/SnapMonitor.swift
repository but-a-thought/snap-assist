import AppKit

/// Sorveglia la finestra in primo piano e segnala quando viene agganciata a
/// metà schermo. Il rilevamento è indipendente da Rectangle: funziona con
/// qualunque strumento (Rectangle, Magnet, scorciatoie, trascinamento).
final class SnapMonitor {
    /// Restituisce true se il suggerimento è stato mostrato davvero.
    var onSnap: ((SnapEvent) -> Bool)?
    var onShouldDismiss: (() -> Void)?

    var isEnabled = true {
        didSet {
            if !isEnabled { onShouldDismiss?() }
        }
    }

    private var timer: Timer?
    private var lastSignature: String?
    private var pendingSignature: String?
    private var currentEvent: SnapEvent?
    private var pickerOpen = false
    private var suppressUntil = Date.distantPast
    private var lastFrames: [CGWindowID: CGRect] = [:]
    private var frameChangedAt = Date.distantPast

    func start() {
        stop()
        let timer = Timer(timeInterval: 0.22, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pickerDidDismiss() {
        pickerOpen = false
        currentEvent = nil
    }

    /// Blocca il rilevamento per qualche istante: serve mentre l'utente
    /// ridimensiona le finestre con la barra, per non far comparire il pannello.
    func pauseDetection(for interval: TimeInterval) {
        suppressUntil = max(suppressUntil, Date().addingTimeInterval(interval))
        pendingSignature = nil
        lastFrames.removeAll()
        frameChangedAt = .distantPast
    }

    /// Allinea lo stato alla finestra in primo piano senza mostrare nulla.
    func syncWithFrontmostWindow() {
        pendingSignature = nil
        lastFrames.removeAll()
        frameChangedAt = .distantPast
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = AX.focusedWindow(pid: app.processIdentifier),
              let raw = AX.frame(window) else { return }

        let rect = ScreenGeometry.appKit(fromAccessibility: raw)
        if let hit = SnapDetector.detect(rect) {
            lastSignature = Self.signature(pid: app.processIdentifier, rect: rect, side: hit.side)
        }
    }

    /// Da chiamare dopo uno spostamento fatto dall'app: evita che la finestra
    /// appena sistemata faccia ricomparire subito il suggerimento.
    func noteProgrammaticMove(pid: pid_t, window: AXUIElement) {
        suppressUntil = Date().addingTimeInterval(1.2)
        pendingSignature = nil
        lastFrames.removeAll()
        frameChangedAt = .distantPast
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, let raw = AX.frame(window) else { return }
            let rect = ScreenGeometry.appKit(fromAccessibility: raw)
            if let hit = SnapDetector.detect(rect) {
                self.lastSignature = Self.signature(pid: pid, rect: rect, side: hit.side)
            }
        }
    }

    // MARK: - Ciclo di controllo

    private func tick() {
        guard isEnabled else { return }

        // Mission Control, Exposé e Launchpad: niente pannello, e se era
        // aperto va chiuso subito.
        if WindowList.isSystemOverlayActive() {
            if pickerOpen { onShouldDismiss?() }
            return
        }

        if pickerOpen {
            guard let event = currentEvent else { return }
            let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let isOurs = frontPid == ProcessInfo.processInfo.processIdentifier
            if let frontPid, frontPid != event.pid, !isOurs {
                onShouldDismiss?()
                return
            }
            if !isStillSnapped(event) { onShouldDismiss?() }
            return
        }

        guard Date() >= suppressUntil else { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular,
              let window = AX.focusedWindow(pid: app.processIdentifier),
              let raw = AX.frame(window) else { return }

        let rect = ScreenGeometry.appKit(fromAccessibility: raw)

        // Osserva i frame di tutte le finestre visibili: un cambiamento del
        // frame della finestra in primo piano significa che è stata appena
        // agganciata (o ridimensionata). Serve a distinguere un nuovo snap da
        // un semplice clic su una finestra che era già a metà schermo.
        let visible = WindowList.allVisibleWindows()
        let focusedID = visible.first(where: { candidate in
            candidate.pid == app.processIdentifier && Self.framesMatch(candidate.frame, raw)
        })?.id

        if let focusedID, let previous = lastFrames[focusedID], !Self.framesMatch(previous, raw) {
            frameChangedAt = Date()
        }

        var currentFrames: [CGWindowID: CGRect] = [:]
        currentFrames.reserveCapacity(visible.count)
        for candidate in visible {
            currentFrames[candidate.id] = candidate.frame
        }
        lastFrames = currentFrames

        guard let hit = SnapDetector.detect(rect) else {
            lastSignature = nil
            pendingSignature = nil
            currentEvent = nil
            return
        }

        let signature = Self.signature(pid: app.processIdentifier, rect: rect, side: hit.side)
        guard signature != lastSignature else { return }

        // Il pannello compare solo per uno snap appena avvenuto: un clic su
        // una finestra già affiancata non deve riaprirlo.
        guard Date().timeIntervalSince(frameChangedAt) < 1.2 else {
            pendingSignature = nil
            return
        }

        // Lo snap deve restare identico per due controlli di fila: evita che
        // il pannello compaia mentre la finestra viene ancora trascinata.
        guard signature == pendingSignature else {
            pendingSignature = signature
            return
        }
        pendingSignature = nil
        lastSignature = signature

        let event = SnapEvent(
            pid: app.processIdentifier,
            windowID: focusedID,
            window: window,
            frame: rect,
            side: hit.side,
            screen: hit.screen,
            target: SnapDetector.oppositeHalf(of: rect, side: hit.side, base: hit.base)
        )

        currentEvent = event
        pickerOpen = onSnap?(event) ?? false
        if !pickerOpen { currentEvent = nil }
    }

    private static func framesMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 4
            && abs(a.minY - b.minY) < 4
            && abs(a.width - b.width) < 4
            && abs(a.height - b.height) < 4
    }

    private func isStillSnapped(_ event: SnapEvent) -> Bool {
        guard let raw = AX.frame(event.window) else { return false }
        let rect = ScreenGeometry.appKit(fromAccessibility: raw)
        guard let hit = SnapDetector.detect(rect) else { return false }
        return hit.side == event.side
    }

    private static func signature(pid: pid_t, rect: NSRect, side: SnapSide) -> String {
        let x = Int(rect.minX.rounded())
        let y = Int(rect.minY.rounded())
        let w = Int(rect.width.rounded())
        let h = Int(rect.height.rounded())
        return "\(pid)|\(side.rawValue)|\(x)|\(y)|\(w)|\(h)"
    }
}
