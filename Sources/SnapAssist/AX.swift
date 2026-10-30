import AppKit
import ApplicationServices

/// Piccolo strato sopra le API Accessibility, usate per leggere la finestra in
/// primo piano e per spostare quella scelta dall'utente.
enum AX {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Mostra il prompt di sistema per l'accesso Accessibilità.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    /// Frame della finestra in coordinate Accessibility (origine in alto a sinistra).
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin = point(element, kAXPositionAttribute),
              let size = size(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Finestra in primo piano dell'app indicata.
    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        for name in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let value = attribute(application, name), CFGetTypeID(value) == AXUIElementGetTypeID() {
                return (value as! AXUIElement)
            }
        }
        if let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] {
            return windows.first
        }
        return nil
    }

    /// Ritrova l'elemento Accessibility di una finestra a partire dal frame
    /// restituito da CGWindowList (le due misure coincidono quasi sempre).
    static func window(pid: pid_t, matching target: CGRect) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        guard let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] else { return nil }

        var best: AXUIElement?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for window in windows {
            guard let candidate = frame(window) else { continue }
            let distance = abs(candidate.minX - target.minX)
                + abs(candidate.minY - target.minY)
                + abs(candidate.width - target.width)
                + abs(candidate.height - target.height)
            if distance < bestDistance {
                bestDistance = distance
                best = window
            }
        }
        return bestDistance <= 200 ? best : nil
    }

    /// Imposta posizione e dimensione. La dimensione viene scritta due volte
    /// perché diverse app correggono l'origine quando cambia il size.
    @discardableResult
    static func setFrame(_ element: AXUIElement, _ frame: CGRect) -> Bool {
        var size = frame.size
        var origin = frame.origin
        var changed = false

        if let value = AXValueCreate(.cgSize, &size) {
            changed = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success || changed
        }
        if let value = AXValueCreate(.cgPoint, &origin) {
            changed = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success || changed
        }
        if let value = AXValueCreate(.cgSize, &size) {
            _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
        return changed
    }

    static func activate(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    static func setSize(_ element: AXUIElement, _ newSize: CGSize) {
        var size = newSize
        if let value = AXValueCreate(.cgSize, &size) {
            _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
    }
}
