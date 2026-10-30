import AppKit

/// Pannello che occupa la metà libera dello schermo: mostra le finestre
/// disponibili e si chiude al primo clic fuori.
final class PickerView: NSView {
    private var cards: [CardView] = []
    private let header = NSTextField(labelWithString: L10n.t("picker.title"))
    private let footnote = NSTextField(labelWithString: "")
    private let background = NSVisualEffectView()
    private let headerPill = NSView()
    private let footnotePill = NSView()

    var onPick: ((WindowCandidate) -> Void)?
    var onCancel: (() -> Void)?

    init(frame: NSRect, items: [WindowCandidate], note: String) {
        super.init(frame: frame)
        wantsLayer = true

        // Vetro scuro: stacca le schede da qualunque finestra ci sia sotto.
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.alphaValue = 0.96
        background.autoresizingMask = [.width, .height]
        addSubview(background)

        headerPill.wantsLayer = true
        headerPill.layer?.cornerRadius = 9
        headerPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.34).cgColor
        addSubview(headerPill)

        header.font = .systemFont(ofSize: 16, weight: .semibold)
        header.textColor = .white
        header.alignment = .center
        header.lineBreakMode = .byTruncatingTail
        header.cell?.usesSingleLineMode = true
        header.shadow = textShadow()
        addSubview(header)

        footnote.stringValue = note
        footnote.font = .systemFont(ofSize: 11, weight: .regular)
        footnote.textColor = NSColor.white.withAlphaComponent(0.68)
        footnote.alignment = .center
        footnote.lineBreakMode = .byTruncatingTail
        footnote.cell?.usesSingleLineMode = true
        footnote.shadow = textShadow()
        addSubview(footnote)

        footnotePill.wantsLayer = true
        footnotePill.layer?.cornerRadius = 7
        footnotePill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        addSubview(footnotePill, positioned: .below, relativeTo: footnote)

        for candidate in items {
            let card = CardView(item: candidate)
            card.onPick = { [weak self] in self?.onPick?(candidate) }
            cards.append(card)
            addSubview(card)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: NSImage, at index: Int) {
        guard cards.indices.contains(index) else { return }
        cards[index].setImage(image)
    }

    private func textShadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return shadow
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        background.frame = bounds

        let inset: CGFloat = 26
        let headerHeight: CGFloat = 28
        let headerGap: CGFloat = 16
        let footnoteHeight: CGFloat = 20
        let footnoteGap: CGFloat = 12
        let gap: CGFloat = 14

        guard !cards.isEmpty else { return }

        let gridWidth = bounds.width - inset * 2
        let availableHeight = bounds.height - inset * 2 - headerHeight - headerGap - footnoteHeight - footnoteGap
        guard gridWidth > 140, availableHeight > 100 else { return }

        let count = cards.count
        let maxColumns = columnsFor(count: count, width: gridWidth)
        guard maxColumns > 0 else { return }

        let rows = Int(ceil(Double(count) / Double(maxColumns)))
        let cardWidth = min((gridWidth - gap * CGFloat(maxColumns - 1)) / CGFloat(maxColumns), 520)
        let cardHeight = min(
            (availableHeight - gap * CGFloat(rows - 1)) / CGFloat(rows),
            cardWidth * 0.72,
            340
        )
        guard cardWidth > 0, cardHeight > 0 else { return }

        let totalWidth = CGFloat(maxColumns) * cardWidth + gap * CGFloat(maxColumns - 1)
        let totalHeight = CGFloat(rows) * cardHeight + gap * CGFloat(rows - 1)
        let clusterHeight = totalHeight + headerGap + headerHeight + footnoteGap + footnoteHeight

        // Tutto il blocco (intestazione, schede, nota) è centrato in verticale.
        let clusterTop = min(bounds.height - inset, (bounds.height + clusterHeight) / 2)
        header.frame = NSRect(
            x: inset,
            y: clusterTop - headerHeight,
            width: gridWidth,
            height: headerHeight
        )

        let headerTextWidth = header.intrinsicContentSize.width
        let headerPillWidth = min(gridWidth, (headerTextWidth > 0 ? headerTextWidth : 340) + 40)
        headerPill.frame = NSRect(
            x: (bounds.width - headerPillWidth) / 2,
            y: header.frame.minY - 3,
            width: headerPillWidth,
            height: headerHeight + 6
        ).integral

        let gridTop = clusterTop - headerHeight - headerGap
        let startX = (bounds.width - totalWidth) / 2

        for row in 0..<rows {
            let first = row * maxColumns
            let last = min(first + maxColumns, count)
            guard first < last else { continue }

            // L'ultima riga, se incompleta, viene centrata.
            let rowCount = last - first
            let rowWidth = CGFloat(rowCount) * cardWidth + gap * CGFloat(rowCount - 1)
            let rowX = startX + (totalWidth - rowWidth) / 2
            let y = gridTop - cardHeight - CGFloat(row) * (cardHeight + gap)

            for index in first..<last {
                let column = index - first
                cards[index].frame = NSRect(
                    x: rowX + CGFloat(column) * (cardWidth + gap),
                    y: y,
                    width: cardWidth,
                    height: cardHeight
                ).integral
            }
        }

        footnote.frame = NSRect(
            x: inset,
            y: gridTop - totalHeight - footnoteGap - footnoteHeight,
            width: gridWidth,
            height: footnoteHeight
        )

        let footnoteTextWidth = footnote.intrinsicContentSize.width
        let footnotePillWidth = min(gridWidth, (footnoteTextWidth > 0 ? footnoteTextWidth : 300) + 26)
        footnotePill.frame = NSRect(
            x: (bounds.width - footnotePillWidth) / 2,
            y: footnote.frame.minY - 1,
            width: footnotePillWidth,
            height: footnoteHeight + 2
        ).integral
    }

    private func columnsFor(count: Int, width: CGFloat) -> Int {
        switch count {
        case 0...1:
            return 1
        case 2, 3, 4:
            return width >= 460 ? 2 : 1
        default:
            if width >= 620 { return 3 }
            return width >= 460 ? 2 : 1
        }
    }

    /// I clic sulle schede arrivano alla scheda, tutti gli altri al pannello
    /// (che li interpreta come "annulla").
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0 else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        for card in cards where card.frame.contains(local) {
            return card
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        onCancel?()
    }

    /// Il pannello non attiva l'app: il primo clic deve arrivare comunque.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

// MARK: - Scheda

final class CardView: NSView {
    let item: WindowCandidate
    var onPick: (() -> Void)?

    private let thumb = ThumbView()
    private let title = NSTextField(labelWithString: "")
    private var hovered = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?

    init(item: WindowCandidate) {
        self.item = item
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 9
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        thumb.icon = item.icon
        addSubview(thumb)

        title.stringValue = item.displayName
        title.font = .systemFont(ofSize: 11.5, weight: .medium)
        title.textColor = NSColor.white.withAlphaComponent(0.92)
        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        title.cell?.truncatesLastVisibleLine = true
        addSubview(title)

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: NSImage) {
        thumb.image = image
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 7
        let titleHeight: CGFloat = 24
        thumb.frame = NSRect(
            x: padding,
            y: padding + titleHeight,
            width: max(0, bounds.width - padding * 2),
            height: max(0, bounds.height - padding * 2 - titleHeight)
        )
        title.frame = NSRect(
            x: padding + 2,
            y: padding,
            width: max(0, bounds.width - padding * 2 - 4),
            height: titleHeight
        )
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor(calibratedWhite: hovered ? 0.21 : 0.14, alpha: 0.97).cgColor
        layer?.borderColor = (hovered
            ? NSColor.controlAccentColor.withAlphaComponent(0.95)
            : NSColor.white.withAlphaComponent(0.09)
        ).cgColor
    }

    // MARK: - Interazione

    override func mouseDown(with event: NSEvent) {
        onPick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    /// Tutti i clic dentro la scheda sono della scheda stessa.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0 else { return nil }
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }
}

// MARK: - Miniatura

final class ThumbView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var icon: NSImage? {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
        bounds.fill()

        if let image {
            let target = bounds
            let imageWidth = max(image.size.width, 1)
            let imageHeight = max(image.size.height, 1)
            let scale = max(target.width / imageWidth, target.height / imageHeight)
            let sourceWidth = target.width / scale
            let sourceHeight = target.height / scale
            let source = NSRect(
                x: (imageWidth - sourceWidth) / 2,
                y: (imageHeight - sourceHeight) / 2,
                width: sourceWidth,
                height: sourceHeight
            )
            image.draw(
                in: target,
                from: source,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.medium]
            )
        } else if let icon {
            let side = min(bounds.width, bounds.height) * 0.32
            let rect = NSRect(
                x: bounds.midX - side / 2,
                y: bounds.midY - side / 2,
                width: side,
                height: side
            )
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.85, respectFlipped: true, hints: nil)
        }
    }
}
