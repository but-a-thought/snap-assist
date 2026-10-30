import AppKit

/// Modalità `--screenshot`: mostra il vero pannello su un desktop simulato con
/// finestre finte, così da poter produrre uno screenshot del README senza
/// contenuti personali.
enum ScreenshotDemo {
    private static let controller = PickerController()
    private static var desktopWindow: NSWindow?

    static func run() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let base = screen.visibleFrame

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .normal
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = MockDesktopView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            visible: base
        )
        window.orderFrontRegardless()
        desktopWindow = window

        let target = NSRect(x: base.midX, y: base.minY, width: base.width / 2, height: base.height)
        let snapped = NSRect(x: base.minX, y: base.minY, width: base.width / 2, height: base.height)
        let event = SnapEvent(
            pid: 0,
            window: AXUIElementCreateSystemWide(),
            frame: snapped,
            side: .left,
            screen: screen,
            target: target
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let items = mockCandidates()
            _ = controller.present(for: event, thumbnails: false, items: items)
            for (index, image) in mockImages().enumerated() {
                controller.setImage(image, at: index)
            }

            let rect = ScreenGeometry.accessibility(fromAppKit: base)
            print("FULL \(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))")
            fflush(stdout)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Dati finti

    private static func mockCandidates() -> [WindowCandidate] {
        [
            WindowCandidate(id: 1, pid: 1001, appName: "Finder", title: "Projects", frame: .zero, icon: nil),
            WindowCandidate(id: 2, pid: 1002, appName: "Safari", title: "Snap Assist — design", frame: .zero, icon: nil),
            WindowCandidate(id: 3, pid: 1003, appName: "Notes", title: "Launch plan", frame: .zero, icon: nil),
            WindowCandidate(id: 4, pid: 1004, appName: "Terminal", title: "build", frame: .zero, icon: nil),
            WindowCandidate(id: 5, pid: 1005, appName: "Mail", title: "Inbox", frame: .zero, icon: nil),
            WindowCandidate(id: 6, pid: 1006, appName: "Music", title: "Focus", frame: .zero, icon: nil)
        ]
    }

    private static func mockImages() -> [NSImage] {
        [finderImage(), safariImage(), notesImage(), terminalImage(), mailImage(), musicImage()]
    }

    // MARK: - Miniature finte

    private static func canvas(_ draw: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: NSSize(width: 640, height: 400), flipped: false) { rect in
            draw(rect)
            return true
        }
    }

    private static func fill(_ rect: NSRect, _ color: NSColor) {
        color.setFill()
        rect.fill()
    }

    private static func windowChrome(_ rect: NSRect, title: String, background: NSColor) {
        fill(rect, background)
        let bar = NSRect(x: 0, y: rect.height - 26, width: rect.width, height: 26)
        fill(bar, NSColor(calibratedWhite: 0.92, alpha: 1))

        let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
        for (index, color) in colors.enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: 12 + CGFloat(index) * 15,
                y: rect.height - 18,
                width: 8,
                height: 8
            )).fill()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1)
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.height - 18),
            withAttributes: attributes
        )
    }

    private static func finderImage() -> NSImage {
        canvas { rect in
            windowChrome(rect, title: "Projects", background: NSColor(calibratedWhite: 0.99, alpha: 1))
            let height = rect.height - 26
            fill(NSRect(x: 0, y: 0, width: 132, height: height), NSColor(calibratedWhite: 0.94, alpha: 1))

            for index in 0..<7 {
                fill(
                    NSRect(x: 16, y: height - 36 - CGFloat(index) * 30, width: 86, height: 7),
                    NSColor(calibratedWhite: 0.74, alpha: 1)
                )
            }

            let colors: [NSColor] = [.systemBlue, .systemOrange, .systemPurple, .systemGreen, .systemPink, .systemTeal]
            for index in 0..<6 {
                let y = height - 42 - CGFloat(index) * 40
                colors[index % colors.count].withAlphaComponent(0.9).setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: 156, y: y, width: 24, height: 24),
                    xRadius: 5,
                    yRadius: 5
                ).fill()
                fill(
                    NSRect(x: 194, y: y + 8, width: 150 + CGFloat((index * 53) % 130), height: 8),
                    NSColor(calibratedWhite: 0.56, alpha: 1)
                )
            }

            fill(NSRect(x: 132, y: height - 26, width: rect.width - 132, height: 26), NSColor(calibratedWhite: 0.9, alpha: 1))
        }
    }

    private static func safariImage() -> NSImage {
        canvas { rect in
            fill(rect, NSColor(calibratedWhite: 0.99, alpha: 1))
            fill(NSRect(x: 0, y: rect.height - 40, width: rect.width, height: 40), NSColor(calibratedWhite: 0.95, alpha: 1))

            let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
            for (index, color) in colors.enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12 + CGFloat(index) * 14, y: rect.height - 26, width: 7, height: 7)).fill()
            }

            NSColor(calibratedWhite: 0.89, alpha: 1).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 130, y: rect.height - 30, width: 380, height: 20),
                xRadius: 6,
                yRadius: 6
            ).fill()

            let hero = NSRect(x: 36, y: rect.height - 232, width: 568, height: 160)
            NSGradient(colors: [
                NSColor(calibratedRed: 0.27, green: 0.45, blue: 0.98, alpha: 1),
                NSColor(calibratedRed: 0.62, green: 0.33, blue: 0.95, alpha: 1)
            ])?.draw(in: hero, angle: -40)

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            ("Snap Assist" as NSString).draw(at: NSPoint(x: 56, y: hero.midY + 6), withAttributes: titleAttributes)

            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85)
            ]
            ("Pick the window that fills the other half." as NSString).draw(
                at: NSPoint(x: 56, y: hero.midY - 18),
                withAttributes: subtitleAttributes
            )

            for index in 0..<7 {
                fill(
                    NSRect(x: 36, y: 118 - CGFloat(index) * 15, width: 280 + CGFloat((index * 61) % 240), height: 6),
                    NSColor(calibratedWhite: 0.8, alpha: 1)
                )
            }
        }
    }

    private static func notesImage() -> NSImage {
        canvas { rect in
            windowChrome(
                rect,
                title: "Launch plan",
                background: NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.94, alpha: 1)
            )

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 1)
            ]
            ("Launch plan" as NSString).draw(at: NSPoint(x: 42, y: rect.height - 92), withAttributes: titleAttributes)

            fill(NSRect(x: 42, y: rect.height - 110, width: 210, height: 2), NSColor(calibratedWhite: 0.8, alpha: 1))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.38, alpha: 1)
            ]
            let lines = [
                "• Snap Assist for macOS",
                "• English + Italian",
                "• Live window previews",
                "• Draggable divider",
                "",
                "Everything stays local.",
                "No account, no analytics."
            ]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(
                    at: NSPoint(x: 42, y: rect.height - 150 - CGFloat(index) * 26),
                    withAttributes: attributes
                )
            }
        }
    }

    private static func terminalImage() -> NSImage {
        canvas { rect in
            windowChrome(rect, title: "build", background: NSColor(calibratedWhite: 0.07, alpha: 1))
            fill(NSRect(x: 0, y: rect.height - 26, width: rect.width, height: 26), NSColor(calibratedWhite: 0.13, alpha: 1))

            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let lines: [(String, NSColor)] = [
                ("$ swift build -c release", NSColor.white.withAlphaComponent(0.9)),
                ("[42/150] Compiling SnapAssist", NSColor(calibratedWhite: 0.65, alpha: 1)),
                ("[150/150] Linking SnapAssist", NSColor(calibratedWhite: 0.65, alpha: 1)),
                ("Build complete! (6.4s)", NSColor.systemGreen),
                ("", .clear),
                ("$ ./SnapAssist --test", NSColor.white.withAlphaComponent(0.9)),
                ("Passati: 59  Falliti: 0  Saltati: 3", NSColor.systemGreen),
                ("$", NSColor.white.withAlphaComponent(0.9))
            ]
            for (index, line) in lines.enumerated() {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: line.1]
                (line.0 as NSString).draw(
                    at: NSPoint(x: 24, y: rect.height - 70 - CGFloat(index) * 24),
                    withAttributes: attributes
                )
            }
        }
    }

    private static func mailImage() -> NSImage {
        canvas { rect in
            windowChrome(rect, title: "Inbox", background: NSColor(calibratedWhite: 0.99, alpha: 1))
            let height = rect.height - 26
            fill(NSRect(x: 0, y: 0, width: 150, height: height), NSColor(calibratedWhite: 0.95, alpha: 1))

            for index in 0..<7 {
                fill(
                    NSRect(x: 18, y: height - 38 - CGFloat(index) * 30, width: 96, height: 7),
                    NSColor(calibratedWhite: 0.74, alpha: 1)
                )
            }

            fill(NSRect(x: 150, y: 0, width: 250, height: height), NSColor(calibratedWhite: 0.97, alpha: 1))
            for index in 0..<6 {
                let y = height - 44 - CGFloat(index) * 44
                fill(NSRect(x: 170, y: y, width: 70, height: 7), NSColor(calibratedWhite: 0.5, alpha: 1))
                fill(NSRect(x: 170, y: y - 12, width: 150 + CGFloat((index * 29) % 60), height: 6), NSColor(calibratedWhite: 0.78, alpha: 1))
            }

            fill(NSRect(x: 400, y: 0, width: 1, height: height), NSColor(calibratedWhite: 0.88, alpha: 1))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1)
            ]
            ("Re: Snap Assist" as NSString).draw(at: NSPoint(x: 422, y: height - 52), withAttributes: attributes)

            for index in 0..<8 {
                fill(
                    NSRect(x: 422, y: height - 90 - CGFloat(index) * 20, width: 140 + CGFloat((index * 47) % 60), height: 6),
                    NSColor(calibratedWhite: 0.8, alpha: 1)
                )
            }
        }
    }

    private static func musicImage() -> NSImage {
        canvas { rect in
            windowChrome(rect, title: "Focus", background: NSColor(calibratedWhite: 0.11, alpha: 1))

            let covers: [(NSColor, NSColor)] = [
                (.systemPink, .systemOrange),
                (.systemBlue, .systemTeal),
                (.systemPurple, .systemIndigo),
                (.systemGreen, .systemYellow)
            ]
            for index in 0..<4 {
                let column = index % 2
                let row = index / 2
                let cover = NSRect(
                    x: 40 + CGFloat(column) * 290,
                    y: rect.height - 200 - CGFloat(row) * 160,
                    width: 120,
                    height: 120
                )
                NSGradient(colors: [covers[index].0, covers[index].1])?.draw(in: cover, angle: 45)
                NSColor.white.withAlphaComponent(0.18).setFill()
                NSBezierPath(ovalIn: cover.insetBy(dx: 36, dy: 36)).fill()

                fill(
                    NSRect(x: cover.maxX + 18, y: cover.midY + 10, width: 96, height: 9),
                    NSColor.white.withAlphaComponent(0.85)
                )
                fill(
                    NSRect(x: cover.maxX + 18, y: cover.midY - 8, width: 70, height: 6),
                    NSColor.white.withAlphaComponent(0.4)
                )
            }
        }
    }
}

// MARK: - Desktop finto

final class MockDesktopView: NSView {
    private let visible: NSRect

    init(frame: NSRect, visible: NSRect) {
        self.visible = visible
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.16, alpha: 1),
            NSColor(calibratedRed: 0.17, green: 0.23, blue: 0.38, alpha: 1)
        ])
        gradient?.draw(in: bounds, angle: -55)

        // Finestra agganciata a sinistra.
        let window = NSRect(
            x: visible.minX,
            y: visible.minY,
            width: visible.width / 2,
            height: visible.height
        )
        NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
        window.fill()

        let barHeight: CGFloat = 30
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        NSRect(x: window.minX, y: window.maxY - barHeight, width: window.width, height: barHeight).fill()

        let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
        for (index, color) in colors.enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: window.minX + 16 + CGFloat(index) * 17,
                y: window.maxY - 19,
                width: 10,
                height: 10
            )).fill()
        }

        let title = "Project brief — Snap Assist"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.38, alpha: 1)
        ]
        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        (title as NSString).draw(
            at: NSPoint(x: window.midX - titleSize.width / 2, y: window.maxY - 21),
            withAttributes: titleAttributes
        )

        let left = window.minX + 56
        let width = window.width - 112
        var y = window.maxY - barHeight - 54

        func drawText(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, spacing: CGFloat = 10) {
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let bounding = (text as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: attributes
            )
            (text as NSString).draw(
                with: NSRect(x: left, y: y - bounding.height, width: width, height: bounding.height),
                options: [.usesLineFragmentOrigin],
                attributes: attributes
            )
            y -= bounding.height + spacing
        }

        let dark = NSColor(calibratedWhite: 0.2, alpha: 1)
        let body = NSColor(calibratedWhite: 0.34, alpha: 1)

        drawText("Project brief", size: 26, weight: .bold, color: dark, spacing: 6)
        drawText("Snap Assist for macOS", size: 14, weight: .regular, color: NSColor(calibratedWhite: 0.55, alpha: 1), spacing: 30)
        drawText("Goal", size: 15, weight: .semibold, color: dark, spacing: 8)
        drawText("Bring the Windows 11 Snap Assist flow to the Mac without replacing the window manager people already use.", size: 13, weight: .regular, color: body, spacing: 24)
        drawText("Scope", size: 15, weight: .semibold, color: dark, spacing: 8)
        drawText("• Detect when a window is snapped to half of the screen.\n• Offer the other windows in the free half, with live previews.\n• Move the chosen window into place and activate it.\n• Keep a draggable divider between side-by-side windows.", size: 13, weight: .regular, color: body, spacing: 24)
        drawText("Notes", size: 15, weight: .semibold, color: dark, spacing: 8)
        drawText("Everything stays local: no network, no analytics, no account. Accessibility is used only to move windows.", size: 13, weight: .regular, color: body, spacing: 10)
    }
}
