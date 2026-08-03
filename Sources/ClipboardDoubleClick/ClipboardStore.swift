import Foundation

/// Gère l'historique : index en mémoire (léger) + corps des textes sur disque
/// (un fichier par entrée), pour supporter sans souci des copies énormes
/// (ex: un texte de 500 pages) sans jamais tout garder en RAM.
final class ClipboardStore {

    private(set) var items: [ClipboardHistoryItem] = []
    var settings: AppSettings

    private let fileManager = FileManager.default
    private let rootDir: URL
    private let bodiesDir: URL
    private let indexURL: URL
    private let settingsURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootDir = appSupport.appendingPathComponent("ClipboardDoubleClick", isDirectory: true)
        bodiesDir = rootDir.appendingPathComponent("bodies", isDirectory: true)
        indexURL = rootDir.appendingPathComponent("index.json")
        settingsURL = rootDir.appendingPathComponent("settings.json")

        try? fileManager.createDirectory(at: bodiesDir, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
        settings.clampDays()

        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data) {
            items = decoded
        }

        prune()
    }

    // MARK: - Ajout

    /// Ajoute une nouvelle copie. plainText est toujours fourni ; rtf est
    /// optionnel et seulement conservé si settings.keepRichText == true et
    /// settings.forcePlainTextOnly == false.
    @discardableResult
    func addCopy(plainText: String, rtf: Data?) -> ClipboardHistoryItem {
        let id = UUID()
        let keepRTF = rtf != nil && settings.keepRichText && !settings.forcePlainTextOnly

        writeBody(id: id, plainText: plainText, rtf: keepRTF ? rtf : nil)

        let item = ClipboardHistoryItem(
            id: id,
            date: Date(),
            preview: ClipboardHistoryItem.makePreview(from: plainText),
            characterCount: plainText.count,
            hasRichText: keepRTF,
            pinned: false
        )
        items.insert(item, at: 0)
        prune()
        saveIndex()
        return item
    }

    // MARK: - Lecture du corps complet (lazy, à la demande - ex: au moment de coller)

    func fullPlainText(for item: ClipboardHistoryItem) -> String {
        let url = bodiesDir.appendingPathComponent("\(item.id.uuidString).txt")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? item.preview
    }

    func richTextData(for item: ClipboardHistoryItem) -> Data? {
        guard item.hasRichText else { return nil }
        let url = bodiesDir.appendingPathComponent("\(item.id.uuidString).rtf")
        return try? Data(contentsOf: url)
    }

    // MARK: - Suppression

    func delete(_ item: ClipboardHistoryItem) {
        items.removeAll { $0.id == item.id }
        removeBodyFiles(id: item.id)
        saveIndex()
    }

    func togglePin(_ item: ClipboardHistoryItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
        saveIndex()
    }

    func clearAll(keepPinned: Bool = true) {
        let toRemove = keepPinned ? items.filter { !$0.pinned } : items
        for item in toRemove {
            removeBodyFiles(id: item.id)
        }
        items = keepPinned ? items.filter { $0.pinned } : []
        saveIndex()
    }

    /// Appelé quand une session se termine, si settings.clearHistoryOnQuit == true.
    func clearOnQuitIfNeeded() {
        if settings.clearHistoryOnQuit {
            clearAll(keepPinned: true)
        }
    }

    // MARK: - Recherche

    func search(_ query: String) -> [ClipboardHistoryItem] {
        guard !query.isEmpty else { return items }
        let lowered = query.lowercased()
        return items.filter { $0.preview.lowercased().contains(lowered) }
    }

    // MARK: - Réglages

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        settings.clampDays()
        saveSettings()
        prune()
    }

    // MARK: - Purge (nb max d'items + nb max de jours, le premier seuil atteint prime)

    private func prune() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -settings.maxDaysToKeep, to: Date())!

        var kept: [ClipboardHistoryItem] = []
        var removed: [ClipboardHistoryItem] = []
        var nonPinnedCount = 0

        for item in items {
            if item.pinned {
                kept.append(item)
                continue
            }
            if item.date < cutoffDate {
                removed.append(item)
                continue
            }
            nonPinnedCount += 1
            if nonPinnedCount > settings.maxItemsToKeep {
                removed.append(item)
            } else {
                kept.append(item)
            }
        }

        if !removed.isEmpty {
            for item in removed {
                removeBodyFiles(id: item.id)
            }
            items = kept
            saveIndex()
        }
    }

    // MARK: - Disque

    private func writeBody(id: UUID, plainText: String, rtf: Data?) {
        let txtURL = bodiesDir.appendingPathComponent("\(id.uuidString).txt")
        try? plainText.write(to: txtURL, atomically: true, encoding: .utf8)
        if let rtf {
            let rtfURL = bodiesDir.appendingPathComponent("\(id.uuidString).rtf")
            try? rtf.write(to: rtfURL)
        }
    }

    private func removeBodyFiles(id: UUID) {
        let txtURL = bodiesDir.appendingPathComponent("\(id.uuidString).txt")
        let rtfURL = bodiesDir.appendingPathComponent("\(id.uuidString).rtf")
        try? fileManager.removeItem(at: txtURL)
        try? fileManager.removeItem(at: rtfURL)
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }
}
