import Foundation

/// Testi dell'interfaccia. La lingua la decide macOS in base alle preferenze
/// dell'utente (e all'eventuale lingua scelta per la singola app).
enum L10n {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
