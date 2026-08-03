import AppKit

/// Menu 2 : réglages. Même style de panel flottant noir que le Menu 1.
/// Clic droit n'importe où = retour au Menu 1 (comme dans le mockup).
final class SettingsPanelController: NSObject {

    private let panel: NSPanel
    private let store: ClipboardStore
    private var outsideClickMonitor: Any?

    var onBack: (() -> Void)?
    var onQuit: (() -> Void)?

    private var maxItemsField: NSTextField!
    private var maxDaysField: NSTextField!
    private var clearOnQuitCheckbox: NSButton!
    private var plainTextOnlyCheckbox: NSButton!
    private var keepRichTextCheckbox: NSButton!

    init(store: ClipboardStore) {
        self.store = store

        let width: CGFloat = 300
        let height: CGFloat = 420

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
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
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .vibrantDark)
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(effectView)

        super.init()
        buildUI(width: width, height: height)

        let clickCatcher = RightClickCatcher(frame: NSRect(x: 0, y: 0, width: width, height: height))
        clickCatcher.onRightClick = { [weak self] in
            self?.dismiss()
        }
        panel.contentView?.addSubview(clickCatcher, positioned: .below, relativeTo: nil)
    }

    func show(at screenPoint: CGPoint) {
        refreshFromStore()
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screenPoint.x - size.width / 2, y: screenPoint.y - size.height / 2))
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func dismiss() {
        removeOutsideClickMonitor()
        panel.orderOut(nil)
        onBack?()
    }

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

    private func refreshFromStore() {
        maxItemsField.stringValue = "\(store.settings.maxItemsToKeep)"
        maxDaysField.stringValue = "\(store.settings.maxDaysToKeep)"
        clearOnQuitCheckbox.state = store.settings.clearHistoryOnQuit ? .on : .off
        plainTextOnlyCheckbox.state = store.settings.forcePlainTextOnly ? .on : .off
        keepRichTextCheckbox.state = store.settings.keepRichText ? .on : .off
    }

    private func buildUI(width: CGFloat, height: CGFloat) {
        guard let content = panel.contentView else { return }

        var y = height - 40

        let title = NSTextField(labelWithString: L10n.t("menu_title"))
        title.font = NSFont.boldSystemFont(ofSize: 15)
        title.textColor = .white
        title.frame = NSRect(x: 12, y: y, width: width - 24, height: 24)
        content.addSubview(title)
        y -= 40

        let clearButton = NSButton(title: L10n.t("settings_clear_history"), target: self, action: #selector(clearHistoryTapped))
        styleAsMenuButton(clearButton, width: width, y: y)
        content.addSubview(clearButton)
        y -= 36

        y -= addLabeledField(to: content, label: L10n.t("settings_max_items"), y: y, width: width, field: &maxItemsField)
        y -= addLabeledField(to: content, label: L10n.t("settings_max_days"), y: y, width: width, field: &maxDaysField)

        clearOnQuitCheckbox = addCheckbox(to: content, label: L10n.t("settings_clear_on_quit"), y: y, width: width)
        y -= 30

        plainTextOnlyCheckbox = addCheckbox(to: content, label: L10n.t("settings_plain_text_only"), y: y, width: width)
        y -= 30

        keepRichTextCheckbox = addCheckbox(to: content, label: L10n.t("settings_keep_rich_text"), y: y, width: width)
        y -= 44

        let quitButton = NSButton(title: L10n.t("settings_quit"), target: self, action: #selector(quitTapped))
        styleAsMenuButton(quitButton, width: width, y: y)
        content.addSubview(quitButton)
        y -= 36

        let aboutButton = NSButton(title: L10n.t("settings_about"), target: self, action: #selector(aboutTapped))
        styleAsMenuButton(aboutButton, width: width, y: y)
        content.addSubview(aboutButton)
        y -= 36

        let supportButton = NSButton(title: L10n.t("settings_support"), target: self, action: #selector(supportTapped))
        styleAsMenuButton(supportButton, width: width, y: y)
        supportButton.contentTintColor = .systemYellow
        content.addSubview(supportButton)
    }

    private func styleAsMenuButton(_ button: NSButton, width: CGFloat, y: CGFloat) {
        button.frame = NSRect(x: 8, y: y, width: width - 16, height: 28)
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .white
        button.font = NSFont.systemFont(ofSize: 13)
    }

    @discardableResult
    private func addLabeledField(to content: NSView, label: String, y: CGFloat, width: CGFloat, field: inout NSTextField!) -> CGFloat {
        let l = NSTextField(wrappingLabelWithString: label)
        l.textColor = .white
        l.font = NSFont.systemFont(ofSize: 12)
        l.frame = NSRect(x: 8, y: y - 4, width: width - 70, height: 32)
        content.addSubview(l)

        let f = NSTextField(frame: NSRect(x: width - 56, y: y + 4, width: 44, height: 22))
        f.alignment = .center
        f.target = self
        f.action = #selector(numericFieldChanged(_:))
        content.addSubview(f)
        field = f

        return 44
    }

    private func addCheckbox(to content: NSView, label: String, y: CGFloat, width: CGFloat) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: label, target: self, action: #selector(checkboxToggled(_:)))
        checkbox.contentTintColor = .white
        checkbox.font = NSFont.systemFont(ofSize: 12)
        checkbox.frame = NSRect(x: 8, y: y, width: width - 16, height: 24)
        // Force le texte en blanc (NSButton checkbox utilise une attributed string).
        let attr = NSMutableAttributedString(string: label)
        attr.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: label.count))
        checkbox.attributedTitle = attr
        content.addSubview(checkbox)
        return checkbox
    }

    private func pushSettingsUpdate() {
        var s = store.settings
        s.maxItemsToKeep = Int(maxItemsField.stringValue) ?? s.maxItemsToKeep
        s.maxDaysToKeep = min(Int(maxDaysField.stringValue) ?? s.maxDaysToKeep, AppSettings.maxDaysHardLimit)
        s.clearHistoryOnQuit = clearOnQuitCheckbox.state == .on
        s.forcePlainTextOnly = plainTextOnlyCheckbox.state == .on
        s.keepRichText = keepRichTextCheckbox.state == .on
        store.updateSettings(s)
        refreshFromStore()
    }

    @objc private func numericFieldChanged(_ sender: NSTextField) {
        pushSettingsUpdate()
    }

    @objc private func checkboxToggled(_ sender: NSButton) {
        pushSettingsUpdate()
    }

    @objc private func clearHistoryTapped() {
        store.clearAll(keepPinned: true)
    }

    @objc private func quitTapped() {
        onQuit?()
    }

    @objc private func aboutTapped() {
        let alert = NSAlert()
        alert.messageText = L10n.t("about_title")
        alert.informativeText = L10n.t("about_message")
        alert.runModal()
    }

    @objc private func supportTapped() {
        if let url = URL(string: "https://buymeacoffee.com/vassi974") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Vue transparente en fond de panel, uniquement là pour capter le clic droit "retour".
private final class RightClickCatcher: NSView {
    var onRightClick: (() -> Void)?
    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Ne capte que le clic droit ; laisse passer le reste aux contrôles au-dessus.
        return super.hitTest(point)
    }
}
