import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let store = ClipboardStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private let tap = RightClickTap()
    private lazy var historyPanel = HistoryPanelController(store: store)
    private lazy var settingsPanel = SettingsPanelController(store: store)

    /// L'app qui était au premier plan juste avant l'ouverture du Menu,
    /// pour pouvoir y coller le texte choisi et lui redonner le focus.
    private var previousFrontmostApp: NSRunningApplication?
    private var lastTriggerScreenPoint: CGPoint = .zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // pas d'icône dans le Dock, utilitaire d'arrière-plan

        guard RightClickTap.requestAccessibilityPermissionIfNeeded() else {
            print("[ClipboardDoubleClick] Permission Accessibilité requise. Autorise l'app dans " +
                  "Réglages Système > Confidentialité et sécurité > Accessibilité, puis relance.")
            return
        }

        monitor.start()
        wireTap()
        wireHistoryPanel()
        wireSettingsPanel()
        tap.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.clearOnQuitIfNeeded()
    }

    // MARK: - Wiring

    private func wireTap() {
        tap.isCurrentAppExcluded = { [weak self] in
            guard let self else { return false }
            guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
            return self.store.settings.excludedBundleIdentifiers.contains(bundleId)
        }

        tap.onDoubleRightClick = { [weak self] cgPoint in
            guard let self else { return }
            self.previousFrontmostApp = NSWorkspace.shared.frontmostApplication
            self.lastTriggerScreenPoint = cgPoint
            self.historyPanel.show(at: self.cocoaPoint(fromCG: cgPoint))
        }
    }

    private func wireHistoryPanel() {
        historyPanel.onConfirmItem = { [weak self] item in
            self?.pasteItem(item)
        }
        historyPanel.onOpenSettings = { [weak self] in
            guard let self else { return }
            self.settingsPanel.show(at: self.cocoaPoint(fromCG: self.lastTriggerScreenPoint))
        }
        historyPanel.onDismiss = { [weak self] in
            self?.previousFrontmostApp?.activate()
        }
    }

    private func wireSettingsPanel() {
        settingsPanel.onBack = { [weak self] in
            guard let self else { return }
            self.historyPanel.show(at: self.cocoaPoint(fromCG: self.lastTriggerScreenPoint))
        }
        settingsPanel.onQuit = {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Charger la sélection dans le presse-papiers système

    /// Le clic gauche de validation recopie simplement l'élément choisi sur le
    /// presse-papiers système — c'est à l'utilisateur de faire Cmd+V lui-même
    /// ensuite. (On a retiré la simulation automatique de Cmd+V : dans les
    /// contextes sans champ éditable au focus, ça produisait juste un bip
    /// d'erreur système sans rien coller.)
    private func pasteItem(_ item: ClipboardHistoryItem) {
        let pasteboard = NSPasteboard.general
        monitor.ignoreNextChange = true
        pasteboard.clearContents()

        if let rtfData = store.richTextData(for: item), store.settings.keepRichText, !store.settings.forcePlainTextOnly {
            pasteboard.setData(rtfData, forType: .rtf)
        }
        pasteboard.setString(store.fullPlainText(for: item), forType: .string)

        previousFrontmostApp?.activate()
    }

    // MARK: - Conversion de coordonnées (CGEvent: origine haut-gauche -> AppKit: origine bas-gauche)

    private func cocoaPoint(fromCG cgPoint: CGPoint) -> NSPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSPoint(x: cgPoint.x, y: primaryHeight - cgPoint.y)
    }
}
