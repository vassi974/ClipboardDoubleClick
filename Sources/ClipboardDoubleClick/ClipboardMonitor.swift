import AppKit

/// Surveille le presse-papiers système par polling (approche standard sur macOS,
/// il n'existe pas de notification native de changement de presse-papiers).
final class ClipboardMonitor {

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let store: ClipboardStore

    /// Mis à true juste avant qu'on écrive nous-mêmes dans le pasteboard
    /// (pour coller un élément de l'historique), afin de ne pas se
    /// re-capturer soi-même comme "nouvelle copie".
    var ignoreNextChange = false

    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = pasteboard.changeCount
    }

    func start(interval: TimeInterval = 0.5) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollOnce()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pollOnce() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        guard let plainText = pasteboard.string(forType: .string), !plainText.isEmpty else {
            return
        }

        // Évite de dupliquer si on recopie deux fois exactement la même chose de suite.
        if let mostRecent = store.items.first, store.fullPlainText(for: mostRecent) == plainText {
            return
        }

        var rtfData: Data? = nil
        if let data = pasteboard.data(forType: .rtf) {
            rtfData = data
        }

        store.addCopy(plainText: plainText, rtf: rtfData)
    }
}
