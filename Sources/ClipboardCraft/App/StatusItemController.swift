import AppKit

/// Menu bar icon with quick access to recent clips.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let services: AppServices
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(services: AppServices) {
        self.services = services
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "list.clipboard.fill", accessibilityDescription: "Clipboard Craft")
            button.image?.isTemplate = true
            button.toolTip = "Clipboard Craft"
        }
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        updateIcon()
    }

    func updateIcon() {
        let paused = services.settings.isPaused
        item.button?.image = NSImage(systemSymbolName: paused ? "pause.circle" : "list.clipboard.fill",
                                     accessibilityDescription: "Clipboard Craft")
        item.button?.image?.isTemplate = true
        item.button?.appearsDisabled = paused
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = services.settings

        let open = add("Open Quick Panel", #selector(openPanel), symbol: "rectangle.and.text.magnifyingglass")
        if let sc = s.quickPanelShortcuts.first { applyShortcut(sc, to: open) }
        let lib = add("Open Library", #selector(openLibrary), symbol: "macwindow")
        if let sc = s.mainWindowShortcut { applyShortcut(sc, to: lib) }

        menu.addItem(.separator())
        let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let recent = services.store.items.prefix(10)
        if recent.isEmpty {
            let empty = NSMenuItem(title: "Nothing copied yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (i, clip) in recent.enumerated() {
            var title = clip.displayTitle.replacingOccurrences(of: "\n", with: " ")
            if title.count > 48 { title = String(title.prefix(47)) + "…" }
            let mi = NSMenuItem(title: title, action: #selector(copyRecent(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            mi.keyEquivalentModifierMask = []
            mi.target = self
            mi.representedObject = clip.id
            mi.image = NSImage(systemSymbolName: clip.kind.symbol, accessibilityDescription: nil)
            mi.toolTip = "Copy to clipboard"
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        let pause = add(s.isPaused ? "Resume Recording" : "Pause Recording", #selector(togglePause),
                        symbol: s.isPaused ? "play.circle" : "pause.circle")
        pause.state = .off
        add("Settings…", #selector(openSettings), key: ",", symbol: "gearshape")
        menu.addItem(.separator())
        add("Quit Clipboard Craft", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, key: String = "", symbol: String? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        if let symbol { mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(mi)
        return mi
    }

    private func applyShortcut(_ s: Shortcut, to item: NSMenuItem) {
        let key = s.keyCode == 49 ? " " : (KeyboardLayout.character(for: UInt16(s.keyCode))?.lowercased() ?? "")
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = s.modifierFlags
    }

    @objc private func openPanel() { services.quickPanel.show() }
    @objc private func openLibrary() { services.windows.showMain() }
    @objc private func openSettings() { services.windows.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func togglePause() {
        services.settings.isPaused.toggle()
        updateIcon()
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let clip = services.store.item(id) else { return }
        services.paste.copy([clip])
    }
}
