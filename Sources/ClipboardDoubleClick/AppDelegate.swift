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
    private var itemBarreMenus: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // pas d'icône dans le Dock, utilitaire d'arrière-plan

        creerIconeBarreMenus()

        // Tout ce qui ne dépend pas d'Accessibilité démarre inconditionnellement :
        // surveillance du presse-papiers (NSPasteboard, aucune permission requise),
        // panneaux, icône barre de menus. Seul le double clic droit a besoin de la
        // permission — sa présence ou son absence ne doit plus jamais faire quitter
        // l'app (bug corrigé le 06/08/2026 : l'ancienne alerte personnalisée
        // dupliquait la fenêtre système ET fermait l'app dans tous les cas, y
        // compris après avoir cliqué "Ouvrir les réglages" — ce qui tuait aussi
        // l'icône barre de menus qu'on venait de créer).
        monitor.start()
        wireTap()
        wireHistoryPanel()
        wireSettingsPanel()

        if RightClickTap.requestAccessibilityPermissionIfNeeded() {
            tap.start()
        }
        // Sans permission : le double clic droit reste simplement inactif. La
        // fenêtre système d'Apple (déclenchée par la ligne au-dessus) suffit à
        // informer l'utilisateur ; l'icône barre de menus reste l'entrée de
        // secours qui marche déjà, sans qu'on ait besoin de répéter le message.
    }

    /// Icône permanente dans la barre de menus : point d'entrée visible qui
    /// ne dépend d'aucune permission — contrairement au double clic droit
    /// (Accessibilité). Clic gauche = ouvre l'historique directement sous
    /// l'icône. Clic droit = menu (ouvrir / quitter).
    private func creerIconeBarreMenus() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let bouton = item.button {
            bouton.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "ClipboardDoubleClick")
            bouton.action = #selector(clicIconeBarreMenus(_:))
            bouton.target = self
            bouton.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        itemBarreMenus = item
    }

    @objc private func clicIconeBarreMenus(_ sender: NSStatusBarButton) {
        guard let evenement = NSApp.currentEvent else { return }
        if evenement.type == .rightMouseUp {
            afficherMenuBarreMenus()
        } else {
            ouvrirDepuisBarreMenus()
        }
    }

    private func afficherMenuBarreMenus() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.t("menu_title"),
                                action: #selector(ouvrirDepuisBarreMenus), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.t("settings_quit"),
                                action: #selector(quitterDepuisBarreMenus), keyEquivalent: ""))
        for entree in menu.items { entree.target = self }

        itemBarreMenus?.menu = menu
        itemBarreMenus?.button?.performClick(nil)
        itemBarreMenus?.menu = nil  // sinon le clic gauche rouvre le menu au lieu d'ouvrir l'historique
    }

    @objc private func quitterDepuisBarreMenus() {
        NSApp.terminate(nil)
    }

    /// Ouvre l'historique sous l'icône de la barre de menus, comme le double
    /// clic droit l'ouvre sous le curseur — même mécanisme, point de départ
    /// différent.
    @objc private func ouvrirDepuisBarreMenus() {
        previousFrontmostApp = NSWorkspace.shared.frontmostApplication
        guard let bouton = itemBarreMenus?.button, let fenetre = bouton.window else { return }
        let bas = NSPoint(x: fenetre.frame.midX, y: fenetre.frame.minY)
        lastTriggerScreenPoint = cgPoint(fromCocoa: bas)
        historyPanel.show(at: bas)
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

    /// Inverse de `cocoaPoint(fromCG:)` — nécessaire pour l'icône barre de
    /// menus, dont la position est nativement en coordonnées Cocoa (frame de
    /// fenêtre), alors que `lastTriggerScreenPoint` est stocké en CG pour
    /// rester cohérent avec le chemin du double clic droit.
    private func cgPoint(fromCocoa cocoaPoint: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: cocoaPoint.x, y: primaryHeight - cocoaPoint.y)
    }
}
