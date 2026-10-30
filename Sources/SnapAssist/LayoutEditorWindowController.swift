import AppKit

/// Anteprima di un layout: usata nella finestra Impostazioni e nell'editor.
final class LayoutThumbnailView: NSView {
    var layout: ZoneLayout {
        didSet { needsDisplay = true }
    }
    var selected = false {
        didSet { needsDisplay = true }
    }
    var interactive = false
    var onSelect: (() -> Void)?

    init(layout: ZoneLayout, interactive: Bool = false) {
        self.layout = layout
        self.interactive = interactive
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        (selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.14)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.45)
        ).setFill()
        background.fill()

        let inset: CGFloat = 8
        let area = bounds.insetBy(dx: inset, dy: inset)
        for zone in layout.zones {
            let rect = NSRect(
                x: area.minX + zone.minX * area.width,
                y: area.minY + (1 - zone.minY - zone.height) * area.height,
                width: zone.width * area.width,
                height: zone.height * area.height
            )
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            (selected
                ? NSColor.controlAccentColor.withAlphaComponent(0.35)
                : NSColor.secondaryLabelColor.withAlphaComponent(0.16)
            ).setFill()
            path.fill()
            NSColor.secondaryLabelColor.withAlphaComponent(0.45).setStroke()
            path.lineWidth = 0.8
            path.stroke()
        }

        if selected {
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            NSColor.controlAccentColor.setStroke()
            border.lineWidth = 2
            border.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard interactive else { return }
        onSelect?()
    }

    override func resetCursorRects() {
        if interactive {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

/// Editor dei layout: preset pronti oppure zone disegnate liberamente.
final class LayoutEditorWindowController: NSWindowController, NSWindowDelegate {
    private var selected: ZoneLayout = LayoutStore.current
    private var presetViews: [LayoutThumbnailView] = []
    private let customCanvas = CustomLayoutEditorView(frame: .zero)
    private let columnsStepper = NSStepper()
    private let rowsStepper = NSStepper()
    private let columnsLabel = NSTextField(labelWithString: "")
    private let rowsLabel = NSTextField(labelWithString: "")

    var onSave: ((ZoneLayout) -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 780),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("layout.title")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        _ = NSApp.setActivationPolicy(.regular)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - Interfaccia

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])

        let heading = NSTextField(labelWithString: L10n.t("layout.title"))
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        stack.addArrangedSubview(heading)

        let hint = NSTextField(wrappingLabelWithString: L10n.t("layout.hint"))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 760
        stack.addArrangedSubview(hint)

        // Galleria dei preset, cinque per riga.
        let perRow = 5
        var currentRow: NSStackView?
        for (index, layout) in ZoneLayout.presets.enumerated() {
            if index % perRow == 0 {
                let row = NSStackView()
                row.orientation = .horizontal
                row.spacing = 10
                stack.addArrangedSubview(row)
                currentRow = row
            }

            let thumbnail = LayoutThumbnailView(layout: layout, interactive: true)
            thumbnail.translatesAutoresizingMaskIntoConstraints = false
            thumbnail.widthAnchor.constraint(equalToConstant: 138).isActive = true
            thumbnail.heightAnchor.constraint(equalToConstant: 82).isActive = true
            thumbnail.toolTip = layout.name
            thumbnail.onSelect = { [weak self] in self?.select(layout) }
            presetViews.append(thumbnail)
            currentRow?.addArrangedSubview(thumbnail)
        }

        stack.addArrangedSubview(separator())

        let customHeading = NSTextField(labelWithString: L10n.t("layout.custom"))
        customHeading.font = .systemFont(ofSize: 13, weight: .semibold)
        customHeading.textColor = .secondaryLabelColor
        stack.addArrangedSubview(customHeading)

        let customRow = NSStackView()
        customRow.orientation = .horizontal
        customRow.alignment = .top
        customRow.spacing = 16

        customCanvas.translatesAutoresizingMaskIntoConstraints = false
        customCanvas.widthAnchor.constraint(equalToConstant: 470).isActive = true
        customCanvas.heightAnchor.constraint(equalToConstant: 260).isActive = true
        customCanvas.onChange = { [weak self] layout in
            guard let self, !layout.zones.isEmpty else { return }
            self.selected = layout
            self.updateSelection()
        }
        customCanvas.setZones(LayoutStore.current.zones)
        customRow.addArrangedSubview(customCanvas)

        let toolbar = NSStackView()
        toolbar.orientation = .vertical
        toolbar.alignment = .leading
        toolbar.spacing = 8

        columnsStepper.minValue = 1
        columnsStepper.maxValue = 6
        columnsStepper.increment = 1
        columnsStepper.integerValue = 3
        columnsStepper.target = self
        columnsStepper.action = #selector(steppersChanged)

        rowsStepper.minValue = 1
        rowsStepper.maxValue = 4
        rowsStepper.increment = 1
        rowsStepper.integerValue = 1
        rowsStepper.target = self
        rowsStepper.action = #selector(steppersChanged)

        if let components = LayoutStore.current.gridComponents() {
            columnsStepper.integerValue = components.columns.count
            rowsStepper.integerValue = components.rows.count
        }

        columnsLabel.font = .systemFont(ofSize: 12)
        rowsLabel.font = .systemFont(ofSize: 12)

        let columnsRow = NSStackView(views: [columnsLabel, columnsStepper])
        columnsRow.orientation = .horizontal
        columnsRow.spacing = 8
        let rowsRow = NSStackView(views: [rowsLabel, rowsStepper])
        rowsRow.orientation = .horizontal
        rowsRow.spacing = 8
        toolbar.addArrangedSubview(columnsRow)
        toolbar.addArrangedSubview(rowsRow)

        let generate = NSButton(title: L10n.t("layout.generate"), target: self, action: #selector(generateGrid))
        generate.bezelStyle = .rounded
        toolbar.addArrangedSubview(generate)

        let clear = NSButton(title: L10n.t("layout.clear"), target: self, action: #selector(clearCanvas))
        clear.bezelStyle = .rounded
        let delete = NSButton(title: L10n.t("layout.delete"), target: self, action: #selector(deleteSelected))
        delete.bezelStyle = .rounded
        let actions = NSStackView(views: [clear, delete])
        actions.orientation = .horizontal
        actions.spacing = 8
        toolbar.addArrangedSubview(actions)

        customRow.addArrangedSubview(toolbar)
        stack.addArrangedSubview(customRow)

        stack.addArrangedSubview(separator())

        let done = NSButton(title: L10n.t("layout.done"), target: self, action: #selector(donePressed))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        stack.addArrangedSubview(done)

        updateStepperLabels()
        updateSelection()
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        line.widthAnchor.constraint(equalToConstant: 772).isActive = true
        return line
    }

    // MARK: - Stato

    private func select(_ layout: ZoneLayout) {
        selected = layout
        customCanvas.setZones(layout.zones)
        updateSelection()
    }

    private func updateSelection() {
        for view in presetViews {
            view.selected = view.layout == selected
        }
        let matchesPreset = ZoneLayout.presets.contains(selected)
        customCanvas.selected = !matchesPreset
    }

    private func updateStepperLabels() {
        columnsLabel.stringValue = "\(L10n.t("layout.columns")): \(columnsStepper.integerValue)"
        rowsLabel.stringValue = "\(L10n.t("layout.rows")): \(rowsStepper.integerValue)"
    }

    @objc private func steppersChanged() {
        updateStepperLabels()
    }

    @objc private func generateGrid() {
        customCanvas.applyGrid(
            columns: columnsStepper.integerValue,
            rows: rowsStepper.integerValue
        )
    }

    @objc private func clearCanvas() {
        customCanvas.clear()
    }

    @objc private func deleteSelected() {
        customCanvas.deleteSelected()
    }

    @objc private func donePressed() {
        onSave?(selected)
        window?.close()
    }
}
