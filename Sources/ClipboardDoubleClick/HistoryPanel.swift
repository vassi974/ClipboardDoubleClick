import AppKit

/// Une ligne affichée dans le Menu 1. La toute première ligne ("Menu") permet
/// de remonter vers les réglages en scrollant tout en haut, comme dans le mockup.
private enum Row: Equatable {
    case menuEntry
    case sectionHeader(String)
    case item(ClipboardHistoryItem)

    var isSelectable: Bool {
        switch self {
        case .menuEntry, .item: return true
        case .sectionHeader: return false
        }
    }
}

/// Vue custom pour intercepter la molette (déplace la sélection au lieu de
/// scroller le contenu classique) et le clic droit (= retour / fermeture).
private final class SelectionScrollView: NSScrollView {
    var onScrollDelta: ((Int) -> Void)?
    var onRightClick: (() -> Void)?

    /// Délai minimum entre deux déplacements de sélection, quel que soit le
    /// nombre d'événements molette envoyés par le matériel du client (souris à
    /// molette "rapide", trackpad avec inertie, etc.) — sans ça une simple
    /// pichenette peut envoyer des dizaines d'événements et sauter du premier
    /// au dernier item d'un coup.
    private let minIntervalBetweenMoves: CFTimeInterval = 0.09
    private var lastMoveTime: CFTimeInterval = 0

    override func scrollWheel(with event: NSEvent) {
        guard event.deltaY != 0 else { return }

        // On ignore la phase d'inertie du trackpad (le défilement qui continue
        // tout seul après que le doigt a quitté la surface) : on ne veut avancer
        // que sur un vrai geste actif, une ligne à la fois.
        if event.momentumPhase != [] {
            return
        }

        let now = CACurrentMediaTime()
        guard now - lastMoveTime >= minIntervalBetweenMoves else { return }
        lastMoveTime = now

        // deltaY > 0 = molette vers le haut (on remonte dans la liste, vers "Menu").
        onScrollDelta?(event.deltaY > 0 ? -1 : 1)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}

/// Petite poignée de redimensionnement en bas à droite du panel (comme un coin
/// de fenêtre classique), avec une icône visuelle en plus du drag réel.
private final class ResizeGripView: NSView {
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    private var lastScreenPoint: NSPoint?
    private let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if let image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil) {
            imageView.image = image
            imageView.contentTintColor = NSColor.white.withAlphaComponent(0.35)
        }
        imageView.frame = bounds
        imageView.imageScaling = .scaleProportionallyDown
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporté") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        lastScreenPoint = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        guard let last = lastScreenPoint else { lastScreenPoint = current; return }
        let dx = current.x - last.x
        let dy = current.y - last.y
        lastScreenPoint = current
        onDrag?(dx, dy)
    }

    override func mouseUp(with event: NSEvent) {
        lastScreenPoint = nil
    }
}

final class HistoryPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    private static let widthDefaultsKey = "HistoryPanel.width"
    private static let heightDefaultsKey = "HistoryPanel.height"
    private static let minSize = NSSize(width: 240, height: 220)
    private static let defaultSize = NSSize(width: 320, height: 360)

    private let panel: NSPanel
    private let effectView: NSVisualEffectView
    private let scrollView: SelectionScrollView
    private let tableView: NSTableView
    private let searchField: NSSearchField
    private let resizeGrip: ResizeGripView

    private let store: ClipboardStore
    private var rows: [Row] = []
    private var selectedIndex: Int = 1 // par défaut : le dernier élément copié (juste après "Menu")
    private var outsideClickMonitor: Any?
    private var windowResizeObserver: Any?

    var onConfirmItem: ((ClipboardHistoryItem) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onDismiss: (() -> Void)?

    init(store: ClipboardStore) {
        self.store = store

        let defaults = UserDefaults.standard
        let savedWidth = defaults.double(forKey: Self.widthDefaultsKey)
        let savedHeight = defaults.double(forKey: Self.heightDefaultsKey)
        let width = savedWidth > 0 ? CGFloat(savedWidth) : Self.defaultSize.width
        let height = savedHeight > 0 ? CGFloat(savedHeight) : Self.defaultSize.height

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.minSize = Self.minSize

        // Les boutons standard (fermer/réduire/zoom) existent toujours pour une
        // fenêtre .titled même quand le titre est masqué — on les cache pour de
        // bon, sinon ils apparaissent en fantôme dans le coin, sous la barre de
        // recherche.
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // Fond flouté vibrant façon Spotlight/Raycast + coins arrondis, au lieu
        // du noir plat.
        effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .vibrantDark)
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]

        // Marge supplémentaire en haut pour que la barre de recherche ne colle
        // pas au bord arrondi de la fenêtre.
        let topInset: CGFloat = 14
        searchField = NSSearchField(frame: NSRect(x: 8, y: height - 32 - topInset, width: width - 16, height: 24))
        searchField.placeholderString = "Rechercher…"
        searchField.autoresizingMask = [.width, .minYMargin]

        scrollView = SelectionScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height - 36 - topInset))
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 26
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = width - 20
        tableView.addTableColumn(column)

        scrollView.documentView = tableView

        resizeGrip = ResizeGripView(frame: NSRect(x: width - 18, y: 2, width: 16, height: 16))
        resizeGrip.autoresizingMask = [.minXMargin, .maxYMargin]

        super.init()

        tableView.dataSource = self
        tableView.delegate = self
        searchField.delegate = self

        // Important : on utilise target/action (déclenché uniquement par un vrai clic
        // souris de l'utilisateur sur une ligne), PAS le délégué de sélection — celui-ci
        // se déclenche aussi pour nos changements de sélection programmatiques (molette),
        // ce qui collerait le contenu à chaque scroll si on s'y branchait.
        tableView.target = self
        tableView.action = #selector(rowClickedByUser)

        scrollView.onScrollDelta = { [weak self] delta in
            self?.moveSelection(by: delta)
        }
        scrollView.onRightClick = { [weak self] in
            self?.dismiss()
        }
        resizeGrip.onDrag = { [weak self] dx, dy in
            self?.handleGripDrag(dx: dx, dy: dy)
        }

        panel.contentView?.addSubview(effectView)
        panel.contentView?.addSubview(scrollView)
        panel.contentView?.addSubview(searchField)
        panel.contentView?.addSubview(resizeGrip)

        windowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.handlePanelResized()
        }
    }

    deinit {
        if let observer = windowResizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Affiche le panel centré sur `screenPoint` (coordonnées écran, origine en bas à gauche comme CGEvent).
    func show(at screenPoint: CGPoint) {
        reload(query: "")
        searchField.stringValue = ""
        selectedIndex = defaultSelectionIndex()

        let size = panel.frame.size
        let origin = NSPoint(x: screenPoint.x - size.width / 2, y: screenPoint.y - size.height / 2)
        panel.setFrameOrigin(clampToScreen(origin: origin, size: size, at: screenPoint))

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        tableView.reloadData()
        applySelectionHighlight()
        installOutsideClickMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func handleGripDrag(dx: CGFloat, dy: CGFloat) {
        let old = panel.frame
        let top = old.maxY
        let newWidth = max(Self.minSize.width, old.width + dx)
        let newHeight = max(Self.minSize.height, old.height - dy)
        let newOriginY = top - newHeight
        panel.setFrame(NSRect(x: old.origin.x, y: newOriginY, width: newWidth, height: newHeight), display: true)
    }

    private func handlePanelResized() {
        let size = panel.frame.size
        UserDefaults.standard.set(Double(size.width), forKey: Self.widthDefaultsKey)
        UserDefaults.standard.set(Double(size.height), forKey: Self.heightDefaultsKey)

        if let column = tableView.tableColumns.first {
            column.width = max(0, tableView.bounds.width - 20)
        }
        tableView.reloadData() // recalcule les frames internes des lignes (largeur des boutons, etc.)
    }

    /// Un clic gauche en dehors de la fenêtre (dans une autre app, sur le bureau, etc.)
    /// referme le panel — addGlobalMonitorForEvents ne reçoit justement QUE les clics
    /// hors de notre propre process, donc les clics sur nos boutons/table restent gérés
    /// normalement en interne sans jamais déclencher ce monitor.
    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func clampToScreen(origin: NSPoint, size: NSSize, at point: CGPoint) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(NSPoint(x: point.x, y: point.y), $0.frame) }) ?? NSScreen.main else {
            return origin
        }
        var o = origin
        o.x = max(screen.frame.minX + 4, min(o.x, screen.frame.maxX - size.width - 4))
        o.y = max(screen.frame.minY + 4, min(o.y, screen.frame.maxY - size.height - 4))
        return o
    }

    func dismiss() {
        removeOutsideClickMonitor()
        panel.orderOut(nil)
        onDismiss?()
    }

    private func reload(query: String) {
        let filtered = store.search(query)
        // Les items épinglés remontent en haut de la liste (en gardant leur ordre
        // relatif entre eux), sous leur propre en-tête ; les autres sont
        // regroupés par jour (Aujourd'hui / Hier / Cette semaine / Plus ancien),
        // toujours du plus récent au plus ancien à l'intérieur de chaque groupe.
        let pinned = filtered.filter { $0.pinned }
        let others = filtered.filter { !$0.pinned }

        var newRows: [Row] = [.menuEntry]

        if !pinned.isEmpty {
            newRows.append(.sectionHeader("Épinglés"))
            newRows.append(contentsOf: pinned.map { Row.item($0) })
        }

        for (label, items) in Self.groupByDay(others) where !items.isEmpty {
            newRows.append(.sectionHeader(label))
            newRows.append(contentsOf: items.map { Row.item($0) })
        }

        rows = newRows
    }

    private static func groupByDay(_ items: [ClipboardHistoryItem]) -> [(String, [ClipboardHistoryItem])] {
        let calendar = Calendar.current
        var today: [ClipboardHistoryItem] = []
        var yesterday: [ClipboardHistoryItem] = []
        var thisWeek: [ClipboardHistoryItem] = []
        var older: [ClipboardHistoryItem] = []

        for item in items {
            if calendar.isDateInToday(item.date) {
                today.append(item)
            } else if calendar.isDateInYesterday(item.date) {
                yesterday.append(item)
            } else if let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: item.date),
                to: calendar.startOfDay(for: Date())
            ).day, days <= 7 {
                thisWeek.append(item)
            } else {
                older.append(item)
            }
        }

        return [
            ("Aujourd'hui", today),
            ("Hier", yesterday),
            ("Cette semaine", thisWeek),
            ("Plus ancien", older),
        ]
    }

    /// 1er item réellement sélectionnable (ignore "Menu" et les en-têtes de section) —
    /// c'est la sélection par défaut à l'ouverture du panel ou après une recherche.
    private func defaultSelectionIndex() -> Int {
        for (idx, row) in rows.enumerated() {
            if case .item = row { return idx }
        }
        return 0
    }

    private func nextSelectableIndex(from start: Int, direction: Int) -> Int? {
        var idx = start + direction
        while idx >= 0 && idx < rows.count {
            if rows[idx].isSelectable { return idx }
            idx += direction
        }
        return nil
    }

    /// Si la sélection courante tombe sur un en-tête (ex: après suppression d'un
    /// item qui a fait disparaître le groupe voisin), on la ramène sur la ligne
    /// sélectionnable la plus proche.
    private func clampSelectionToSelectable() {
        guard !rows.isEmpty else { selectedIndex = 0; return }
        if rows.indices.contains(selectedIndex), rows[selectedIndex].isSelectable { return }
        if let next = nextSelectableIndex(from: selectedIndex - 1, direction: 1) {
            selectedIndex = next
        } else if let prev = nextSelectableIndex(from: rows.count, direction: -1) {
            selectedIndex = prev
        } else {
            selectedIndex = 0
        }
    }

    private func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { return }
        if let next = nextSelectableIndex(from: selectedIndex, direction: delta) {
            selectedIndex = next
            applySelectionHighlight()
        }
    }

    private func applySelectionHighlight() {
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }

    private func confirmCurrentSelection() {
        guard rows.indices.contains(selectedIndex) else { return }
        removeOutsideClickMonitor()
        switch rows[selectedIndex] {
        case .menuEntry:
            panel.orderOut(nil)
            onOpenSettings?()
        case .item(let item):
            panel.orderOut(nil)
            onConfirmItem?(item)
        case .sectionHeader:
            break // pas sélectionnable, ne devrait pas arriver
        }
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else { return tableView.rowHeight }
        if case .sectionHeader = rows[row] { return 20 }
        return 26
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        return rows[row].isSelectable
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rowValue = rows[row]

        if case .sectionHeader(let title) = rowValue {
            let height: CGFloat = 20
            let container = NSView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: height))
            let label = NSTextField(labelWithString: title.uppercased())
            label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            label.textColor = NSColor.white.withAlphaComponent(0.4)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.frame = NSRect(x: 8, y: 2, width: container.bounds.width - 16, height: 14)
            label.autoresizingMask = [.width]
            container.addSubview(label)
            return container
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 26))

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.frame = NSRect(x: 8, y: 4, width: container.bounds.width - 70, height: 18)
        label.autoresizingMask = [.width]

        switch rowValue {
        case .sectionHeader:
            break // déjà traité ci-dessus
        case .menuEntry:
            label.stringValue = "Menu"
            label.font = NSFont.boldSystemFont(ofSize: 13)
            container.addSubview(label)

            // Séparateur visuel entre "Menu" et le 1er item de l'historique,
            // collé au bas de cette ligne.
            let separator = NSView(frame: NSRect(x: 8, y: 0, width: container.bounds.width - 16, height: 1))
            separator.wantsLayer = true
            separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
            separator.autoresizingMask = [.width]
            container.addSubview(separator)

        case .item(let item):
            label.stringValue = item.preview
            container.addSubview(label)

            // Identifiant = l'UUID de l'item (pas l'index de ligne) : ça reste
            // valide même si la liste a été retriée (ex: un item qui vient
            // d'être épinglé et qui a sauté en haut de la liste) entre le
            // moment où la vue a été construite et le clic.
            let itemIdentifier = NSUserInterfaceItemIdentifier(item.id.uuidString)

            let deleteButton = NSButton(image: symbolImage("xmark.circle.fill"), target: self, action: #selector(deleteButtonClicked(_:)))
            deleteButton.isBordered = false
            deleteButton.imagePosition = .imageOnly
            // Un item épinglé est protégé : la croix est désactivée et grisée,
            // il faut d'abord le désépingler (clic maladroit = pas de perte).
            deleteButton.isEnabled = !item.pinned
            deleteButton.contentTintColor = item.pinned ? NSColor.white.withAlphaComponent(0.25) : .systemRed
            deleteButton.frame = NSRect(x: container.bounds.width - 26, y: 3, width: 18, height: 18)
            deleteButton.autoresizingMask = [.minXMargin]
            deleteButton.identifier = itemIdentifier
            container.addSubview(deleteButton)

            let pinIconName = item.pinned ? "pin.fill" : "pin"
            let pinButton = NSButton(image: symbolImage(pinIconName), target: self, action: #selector(pinButtonClicked(_:)))
            pinButton.isBordered = false
            pinButton.imagePosition = .imageOnly
            pinButton.contentTintColor = item.pinned ? .systemYellow : NSColor.white.withAlphaComponent(0.5)
            pinButton.frame = NSRect(x: container.bounds.width - 48, y: 3, width: 18, height: 18)
            pinButton.autoresizingMask = [.minXMargin]
            pinButton.identifier = itemIdentifier
            container.addSubview(pinButton)
        }

        return container
    }

    private func symbolImage(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        return rowView
    }

    private func item(for sender: NSButton) -> ClipboardHistoryItem? {
        guard let idString = sender.identifier?.rawValue, let uuid = UUID(uuidString: idString) else { return nil }
        return store.items.first { $0.id == uuid }
    }

    @objc private func deleteButtonClicked(_ sender: NSButton) {
        guard let item = item(for: sender) else { return }
        // Double sécurité : même si jamais le bouton désactivé était
        // contourné, un item épinglé ne se supprime pas directement.
        guard !item.pinned else { return }
        store.delete(item)
        let query = searchField.stringValue
        reload(query: query)
        clampSelectionToSelectable()
        tableView.reloadData()
        applySelectionHighlight()
    }

    @objc private func pinButtonClicked(_ sender: NSButton) {
        guard let item = item(for: sender) else { return }
        store.togglePin(item)
        let query = searchField.stringValue
        reload(query: query)
        clampSelectionToSelectable()
        tableView.reloadData()
        applySelectionHighlight()
    }

    // Un simple clic gauche sur une ligne = on la sélectionne ET on la valide direct.
    // (déclenché uniquement par un vrai clic utilisateur, voir tableView.action ci-dessus)
    @objc private func rowClickedByUser() {
        let row = tableView.clickedRow
        guard row >= 0, rows.indices.contains(row), rows[row].isSelectable else { return }
        selectedIndex = row
        confirmCurrentSelection()
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        reload(query: searchField.stringValue)
        selectedIndex = defaultSelectionIndex()
        tableView.reloadData()
        applySelectionHighlight()
    }
}
