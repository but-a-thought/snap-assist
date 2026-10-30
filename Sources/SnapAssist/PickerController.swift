import AppKit
import ScreenCaptureKit

final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Crea e gestisce il pannello di scelta nella metà libera dello schermo.
final class PickerController {
    /// Chiamata con la finestra scelta e la metà di destinazione.
    var onPick: ((WindowCandidate, NSRect) -> Void)?
    var onDismiss: (() -> Void)?

    private var panel: PickerPanel?
    private var view: PickerView?
    private var target: NSRect = .zero
    private var previousApp: NSRunningApplication?
    private var captureTask: Task<Void, Never>?
    private var globalMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localMonitor: Any?

    @discardableResult
    func present(for event: SnapEvent, thumbnails: Bool, items: [WindowCandidate]? = nil) -> Bool {
        dismiss(silently: true)

        let excluded = ScreenGeometry.accessibility(fromAppKit: event.frame)
        let candidates = items ?? WindowList.candidates(
            excludingID: event.windowID,
            excludingFrame: event.windowID == nil ? excluded : nil
        )
        guard !candidates.isEmpty else { return false }

        let canCapture = thumbnails && CGPreflightScreenCaptureAccess()
        let note: String
        if thumbnails && !canCapture {
            note = L10n.t("picker.hint.noPreviews")
        } else {
            note = L10n.t("picker.hint")
        }

        let frame = event.target
        let panel = PickerPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let content = PickerView(
            frame: NSRect(origin: .zero, size: frame.size),
            items: candidates,
            note: note
        )
        content.autoresizingMask = [.width, .height]
        content.onCancel = { [weak self] in self?.dismiss() }
        content.onPick = { [weak self] candidate in
            guard let self else { return }
            let destination = self.target
            self.dismiss(restoreFocus: false)
            self.onPick?(candidate, destination)
        }

        panel.contentView = content
        panel.setFrame(frame, display: true)
        content.layoutSubtreeIfNeeded()
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        self.view = content
        self.target = frame
        self.previousApp = NSWorkspace.shared.frontmostApplication

        installMonitors()
        if canCapture { loadThumbnails(candidates) }
        return true
    }

    func setImage(_ image: NSImage, at index: Int) {
        view?.setImage(image, at: index)
    }

    func dismiss(silently: Bool = false, restoreFocus: Bool = true) {
        removeMonitors()
        captureTask?.cancel()
        captureTask = nil

        guard let panel else { return }
        self.panel = nil
        self.view = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.contentView = nil
        })

        if !silently { onDismiss?() }

        // Se il clic ha attivato l'app (non dovrebbe, il pannello non è
        // attivante), restituiamo il focus all'app che stava usando l'utente.
        if restoreFocus, NSApp.isActive, let previousApp {
            previousApp.activate()
        }
    }

    // MARK: - Monitor eventi

    private func installMonitors() {
        removeMonitors()

        // Un clic in qualunque altra app = annulla.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.dismiss()
        }

        // Esc funziona anche se l'app non è in primo piano (richiede
        // Accessibilità, che serve già per il resto).
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            self?.dismiss()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.dismiss()
            return nil
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        globalKeyMonitor = nil
        localMonitor = nil
    }

    // MARK: - Anteprime

    private func loadThumbnails(_ candidates: [WindowCandidate]) {
        captureTask = Task { [weak self] in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
                return
            }
            if Task.isCancelled { return }

            var windowsByID: [CGWindowID: SCWindow] = [:]
            for window in content.windows {
                windowsByID[window.windowID] = window
            }

            await withTaskGroup(of: (Int, CGImage?).self) { group in
                for (index, candidate) in candidates.enumerated() {
                    guard let window = windowsByID[candidate.id] else { continue }
                    let size = window.frame.size
                    group.addTask {
                        let configuration = SCStreamConfiguration()
                        let maxSide: CGFloat = 640
                        let scale = min(
                            maxSide / max(size.width, 1),
                            maxSide / max(size.height, 1),
                            2
                        )
                        configuration.width = max(2, Int(size.width * scale))
                        configuration.height = max(2, Int(size.height * scale))
                        configuration.showsCursor = false
                        configuration.ignoreShadowsSingleWindow = true

                        let filter = SCContentFilter(desktopIndependentWindow: window)
                        guard let image = try? await SCScreenshotManager.captureImage(
                            contentFilter: filter,
                            configuration: configuration
                        ) else { return (index, nil) }
                        return (index, image)
                    }
                }

                for await (index, image) in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        return
                    }
                    guard let image else { continue }
                    let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                    await MainActor.run { [weak self] in
                        self?.view?.setImage(nsImage, at: index)
                    }
                }
            }
        }
    }
}
