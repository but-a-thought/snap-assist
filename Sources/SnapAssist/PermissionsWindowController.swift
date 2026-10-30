import AppKit
import ApplicationServices
import CoreGraphics

/// Finestra con i due permessi richiesti e i pulsanti che aprono direttamente
/// i pannelli di Sistema. Si aggiorna da sola mentre è aperta.
final class PermissionsWindowController: NSWindowController, NSWindowDelegate {
    private let accessibilityIcon = NSImageView()
    private let accessibilityStatus = NSTextField(labelWithString: "")
    private let screenIcon = NSImageView()
    private let screenStatus = NSTextField(labelWithString: "")
    private let suggestSwitch = NSSwitch()
    private let previewSwitch = NSSwitch()
    private let dividerSwitch = NSSwitch()
    private var refreshTimer: Timer?

    var onSuggestChanged: ((Bool) -> Void)?
    var onPreviewsChanged: ((Bool) -> Void)?
    var onDividerChanged: ((Bool) -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("permissions.title")
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Apertura

    func show() {
        // Mentre si sistemano i permessi l'app compare nel Dock e in ⌘Tab,
        // così la finestra si ritrova facilmente.
        _ = NSApp.setActivationPolicy(.regular)
        refresh()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        startTimer()

        // La transizione da app di menu ad app normale non è immediata:
        // riproviamo ad attivare al giro successivo del run loop.
        DispatchQueue.main.async { [weak self] in
            NSApp.activate()
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        _ = NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Interfaccia

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])

        let heading = NSTextField(labelWithString: L10n.t("settings.heading"))
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        stack.addArrangedSubview(heading)

        let behavior = NSTextField(labelWithString: L10n.t("settings.behavior"))
        behavior.font = .systemFont(ofSize: 13, weight: .semibold)
        behavior.textColor = .secondaryLabelColor
        stack.addArrangedSubview(behavior)

        stack.addArrangedSubview(toggleRow(
            title: L10n.t("settings.suggest"),
            toggle: suggestSwitch,
            action: #selector(suggestChanged)
        ))
        stack.addArrangedSubview(toggleRow(
            title: L10n.t("settings.previews"),
            toggle: previewSwitch,
            action: #selector(previewsChanged)
        ))
        stack.addArrangedSubview(toggleRow(
            title: L10n.t("settings.divider"),
            toggle: dividerSwitch,
            action: #selector(dividerChanged)
        ))

        stack.addArrangedSubview(separator())

        let permissionsHeading = NSTextField(labelWithString: L10n.t("settings.permissions"))
        permissionsHeading.font = .systemFont(ofSize: 17, weight: .semibold)
        stack.addArrangedSubview(permissionsHeading)

        let subtitle = NSTextField(wrappingLabelWithString: L10n.t("permissions.intro"))
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = 530

        stack.addArrangedSubview(subtitle)
        stack.addArrangedSubview(separator())

        stack.addArrangedSubview(section(
            icon: accessibilityIcon,
            status: accessibilityStatus,
            title: L10n.t("permissions.accessibility"),
            description: L10n.t("permissions.accessibility.detail"),
            action: #selector(openAccessibility)
        ))

        stack.addArrangedSubview(separator())

        stack.addArrangedSubview(section(
            icon: screenIcon,
            status: screenStatus,
            title: L10n.t("permissions.screen"),
            description: L10n.t("permissions.screen.detail"),
            action: #selector(openScreenRecording)
        ))

        let hint = NSTextField(wrappingLabelWithString: L10n.t("permissions.hint"))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.preferredMaxLayoutWidth = 530

        stack.addArrangedSubview(hint)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 10

        let restart = NSButton(title: L10n.t("permissions.restart"), target: self, action: #selector(restartApp))
        restart.bezelStyle = .rounded
        let close = NSButton(title: L10n.t("permissions.close"), target: self, action: #selector(closePanel))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\r"

        actions.addArrangedSubview(restart)
        actions.addArrangedSubview(close)
        stack.addArrangedSubview(actions)

        refresh()
    }

    private func section(
        icon: NSImageView,
        status: NSTextField,
        title: String,
        description: String,
        action: Selector
    ) -> NSView {        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6

        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 8

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 17).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 17).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)

        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor

        let button = NSButton(title: L10n.t("permissions.open"), target: self, action: action)
        button.bezelStyle = .rounded

        header.addArrangedSubview(icon)
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(status)
        header.addArrangedSubview(button)

        let descriptionLabel = NSTextField(wrappingLabelWithString: description)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.preferredMaxLayoutWidth = 530

        container.addArrangedSubview(header)
        container.addArrangedSubview(descriptionLabel)
        return container
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        line.widthAnchor.constraint(equalToConstant: 532).isActive = true
        return line
    }

    private func toggleRow(title: String, toggle: NSSwitch, action: Selector) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        toggle.target = self
        toggle.action = action

        let row = NSStackView(views: [label, spacer, toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: 532).isActive = true
        return row
    }

    /// Allinea gli interruttori alle preferenze correnti.
    func configure(suggest: Bool, previews: Bool, divider: Bool) {
        suggestSwitch.state = suggest ? .on : .off
        previewSwitch.state = previews ? .on : .off
        dividerSwitch.state = divider ? .on : .off
    }

    // MARK: - Stato

    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let trusted = AX.isTrusted
        accessibilityStatus.stringValue = L10n.t(trusted ? "permissions.status.granted" : "permissions.status.needed")
        accessibilityIcon.image = symbol(trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        accessibilityIcon.contentTintColor = trusted ? .systemGreen : .systemOrange

        let granted = CGPreflightScreenCaptureAccess()
        screenStatus.stringValue = L10n.t(granted ? "permissions.status.granted" : "permissions.status.needed")
        screenIcon.image = symbol(granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        screenIcon.contentTintColor = granted ? .systemGreen : .systemOrange
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    // MARK: - Azioni

    @objc private func suggestChanged() {
        onSuggestChanged?(suggestSwitch.state == .on)
    }

    @objc private func previewsChanged() {
        onPreviewsChanged?(previewSwitch.state == .on)
    }

    @objc private func dividerChanged() {
        onDividerChanged?(dividerSwitch.state == .on)
    }

    @objc private func openAccessibility() {
        AX.requestTrust()
        openSettings("Privacy_Accessibility")
    }

    @objc private func openScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        openSettings("Privacy_ScreenCapture")
    }

    private func openSettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func restartApp() {
        let path = Bundle.main.bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.6; open '\(path)'"]
        try? process.run()
        NSApp.terminate(nil)
    }

    @objc private func closePanel() {
        window?.close()
    }
}
