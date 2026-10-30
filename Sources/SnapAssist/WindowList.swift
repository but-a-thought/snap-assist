import AppKit
import CoreGraphics

struct WindowCandidate {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    /// Frame in coordinate CoreGraphics / Accessibility (origine in alto a sinistra).
    let frame: CGRect
    let icon: NSImage?

    var displayName: String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? appName : "\(appName) · \(clean)"
    }
}

/// Finestra visibile ridotta all'essenziale, usata per rilevare le coppie
/// affiancate.
struct VisibleWindow {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
}

/// Finestra di sistema (Dock) usata per capire se è attivo Mission Control.
struct SystemWindow {
    let pid: pid_t
    let layer: Int
    let frame: CGRect
}

enum WindowList {
    /// Mission Control, Exposé e Launchpad sono disegnati dal Dock con una
    /// finestra a tutto schermo sopra a tutto. In quel caso il pannello di
    /// scelta non deve comparire (né restare aperto).
    static func isSystemOverlay(windows: [SystemWindow], dockPid: pid_t, screens: [NSScreen]) -> Bool {
        for window in windows {
            guard window.pid == dockPid, window.layer >= 18 else { continue }
            let coversScreen = screens.contains { screen in
                window.frame.width >= screen.frame.width * 0.8
                    && window.frame.height >= screen.frame.height * 0.8
            }
            if coversScreen { return true }
        }
        return false
    }

    static func isSystemOverlayActive() -> Bool {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        guard let dockPid = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier else { return false }

        var windows: [SystemWindow] = []
        for info in raw {
            guard let layer = number(info[kCGWindowLayer as String])?.intValue, layer >= 18 else { continue }
            guard let pid = number(info[kCGWindowOwnerPID as String])?.int32Value, pid == dockPid else { continue }
            guard let frame = bounds(from: info) else { continue }
            windows.append(SystemWindow(pid: pid, layer: layer, frame: frame))
        }

        return isSystemOverlay(windows: windows, dockPid: dockPid, screens: NSScreen.screens)
    }

    /// Tutte le finestre visibili normali, dalla più in primo piano alla più
    /// indietro. Usata dalla barra di ridimensionamento.
    static func allVisibleWindows(limit: Int = 80) -> [VisibleWindow] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let myPid = ProcessInfo.processInfo.processIdentifier
        var result: [VisibleWindow] = []

        for info in raw {
            if result.count >= limit { break }
            guard let layer = number(info[kCGWindowLayer as String])?.intValue, layer == 0 else { continue }
            guard let alpha = number(info[kCGWindowAlpha as String])?.doubleValue, alpha > 0.05 else { continue }
            guard let pid = number(info[kCGWindowOwnerPID as String])?.int32Value, pid != myPid else { continue }
            guard let id = number(info[kCGWindowNumber as String])?.uint32Value else { continue }
            guard let frame = bounds(from: info) else { continue }
            guard frame.width >= 180, frame.height >= 120 else { continue }

            result.append(VisibleWindow(id: id, pid: pid, frame: frame))
        }

        return result
    }

    /// Finestre visibili, dalla più in primo piano alla più indietro.
    /// Esclude le finestre dell'app stessa e quella appena agganciata, per ID
    /// (non per frame: un'altra finestra può trovarsi sullo stesso rettangolo).
    static func candidates(
        excludingID: CGWindowID? = nil,
        excludingFrame: CGRect? = nil,
        limit: Int = 9
    ) -> [WindowCandidate] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let myPid = ProcessInfo.processInfo.processIdentifier
        var appCache: [pid_t: (name: String, icon: NSImage?)] = [:]
        var seen = Set<String>()
        var result: [WindowCandidate] = []

        for info in raw {
            if result.count >= limit { break }

            guard let layer = number(info[kCGWindowLayer as String])?.intValue, layer == 0 else { continue }
            guard let alpha = number(info[kCGWindowAlpha as String])?.doubleValue, alpha > 0.05 else { continue }
            guard let pid = number(info[kCGWindowOwnerPID as String])?.int32Value, pid != myPid else { continue }
            guard let id = number(info[kCGWindowNumber as String])?.uint32Value else { continue }
            guard let frame = bounds(from: info) else { continue }
            guard frame.width >= 180, frame.height >= 120 else { continue }

            guard !isExcluded(
                id: id,
                frame: frame,
                excludingID: excludingID,
                excludingFrame: excludingFrame
            ) else { continue }

            guard let app = appInfo(pid: pid, cache: &appCache) else { continue }

            let key = "\(pid)|\(Int(frame.minX))|\(Int(frame.minY))|\(Int(frame.width))|\(Int(frame.height))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            result.append(WindowCandidate(
                id: id,
                pid: pid,
                appName: app.name,
                title: (info[kCGWindowName as String] as? String) ?? "",
                frame: frame,
                icon: app.icon
            ))
        }

        return result
    }

    private static func number(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }

    static func isExcluded(
        id: CGWindowID,
        frame: CGRect,
        excludingID: CGWindowID?,
        excludingFrame: CGRect?
    ) -> Bool {
        if let excludingID, id == excludingID { return true }
        if let excludingFrame {
            let distance = abs(frame.minX - excludingFrame.minX)
                + abs(frame.minY - excludingFrame.minY)
                + abs(frame.width - excludingFrame.width)
                + abs(frame.height - excludingFrame.height)
            if distance < 40 { return true }
        }
        return false
    }

    private static func bounds(from info: [String: Any]) -> CGRect? {
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
              let x = number(dict["X"])?.doubleValue,
              let y = number(dict["Y"])?.doubleValue,
              let width = number(dict["Width"])?.doubleValue,
              let height = number(dict["Height"])?.doubleValue else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func appInfo(
        pid: pid_t,
        cache: inout [pid_t: (name: String, icon: NSImage?)]
    ) -> (name: String, icon: NSImage?)? {
        if let cached = cache[pid] { return cached }
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy != .prohibited else { return nil }
        let info = (app.localizedName ?? "App", app.icon)
        cache[pid] = info
        return info
    }

    /// True se una finestra occupa già l'area indicata (cioè è agganciata lì).
    /// Serve a non proporre il pannello su una metà già piena.
    static func isOccupied(_ rect: CGRect, tolerance: CGFloat = 26) -> Bool {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        let myPid = ProcessInfo.processInfo.processIdentifier
        for info in raw {
            guard let layer = number(info[kCGWindowLayer as String])?.intValue, layer == 0 else { continue }
            guard let alpha = number(info[kCGWindowAlpha as String])?.doubleValue, alpha > 0.05 else { continue }
            guard let pid = number(info[kCGWindowOwnerPID as String])?.int32Value, pid != myPid else { continue }
            guard let frame = bounds(from: info) else { continue }

            let horizontal = abs(frame.minX - rect.minX) <= max(tolerance, rect.width * 0.06)
                && abs(frame.width - rect.width) <= max(tolerance, rect.width * 0.06)
            let vertical = abs(frame.minY - rect.minY) <= max(tolerance, rect.height * 0.06)
                && abs(frame.height - rect.height) <= max(tolerance, rect.height * 0.06)
            if horizontal && vertical { return true }
        }
        return false
    }
}
