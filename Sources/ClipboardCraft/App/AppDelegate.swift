import AppKit
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var services: AppServices { AppServices.shared }
    private var statusItem: StatusItemController?
    private var maintenanceTimer: Timer?

    private enum HotKeyID { static let quickPanel: UInt32 = 1; static let library: UInt32 = 2 }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let showcase = Showcase.isActive
        #else
        let showcase = false
        #endif

        // Single instance.
        if !showcase, let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).first { $0 != .current }?.activate()
            NSApp.terminate(nil)
            return
        }

        let s = services.settings
        s.applyAppearance()
        s.onAppearanceChanged = { AppSettings.shared.applyAppearance() }
        s.onShortcutsChanged = { [weak self] in self?.registerHotKeys() }

        services.store.load()
        NSApp.mainMenu = buildMainMenu()
        _ = services.quickPanel
        _ = services.windows
        #if DEBUG
        if showcase { Showcase.run(services); return }
        #endif
        statusItem = StatusItemController(services: services)
        registerHotKeys()
        services.monitor.start()

        // Ask for Accessibility up front (macOS shows its own dialog) so direct paste works on first use.
        if s.pasteDirectly, s.hasCompletedOnboarding, !services.paste.hasAccessibilityAccess {
            services.paste.requestAccessibilityAccess()
        }

        withObservationTracking({ _ = s.isPaused }, onChange: { [weak self] in
            DispatchQueue.main.async { self?.observePause() }
        })
        observePanelSettings()

        let t = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.services.store.runMaintenance() }
        }
        RunLoop.main.add(t, forMode: .common)
        maintenanceTimer = t

        if !s.hasCompletedOnboarding {
            services.windows.showMain()
            services.library.showOnboarding = true
        }
        #if DEBUG
        DebugSnapshots.runIfRequested(services)
        #endif
    }

    private func observePause() {
        statusItem?.updateIcon()
        withObservationTracking({ _ = services.settings.isPaused }, onChange: { [weak self] in
            DispatchQueue.main.async { self?.observePause() }
        })
    }

    private func observePanelSettings() {
        withObservationTracking({
            _ = services.settings.showPreviewInPanel
            _ = services.settings.panelPosition
        }, onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.services.quickPanel.settingsChanged()
                self?.observePanelSettings()
            }
        })
    }

    private func registerHotKeys() {
        let s = services.settings
        HotKeyCenter.shared.register(id: HotKeyID.quickPanel, shortcuts: s.quickPanelShortcuts) { [weak self] in
            self?.services.quickPanel.toggle()
        }
        HotKeyCenter.shared.register(id: HotKeyID.library, shortcuts: s.mainWindowShortcut.map { [$0] } ?? []) { [weak self] in
            self?.services.windows.toggleMain()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { services.windows.showMain() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        services.monitor.stop()
        services.store.purgeTrash()
        services.store.db.checkpoint()
    }

    // MARK: Menu actions

    @objc func openSettings(_ sender: Any?) { services.windows.showSettings() }
    @objc func openLibrary(_ sender: Any?) { services.windows.showMain() }
    @objc func openQuickPanel(_ sender: Any?) { services.quickPanel.show() }
    @objc func importFiles(_ sender: Any?) { Importer.chooseFilesToImport() }
    @objc func togglePause(_ sender: Any?) { services.settings.isPaused.toggle() }

    @objc func newCollection(_ sender: Any?) {
        services.windows.showMain()
        services.library.collectionEditor = CollectionEditorState()
    }

    @objc func focusSearch(_ sender: Any?) {
        services.windows.showMain()
        services.library.searchFocused = true
    }

    @objc func viewAsList(_ sender: Any?) { services.library.viewMode = .list }
    @objc func viewAsGrid(_ sender: Any?) { services.library.viewMode = .grid }

    @objc func showWelcome(_ sender: Any?) {
        services.windows.showMain()
        services.library.showOnboarding = true
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(togglePause(_:)):
            menuItem.title = services.settings.isPaused ? "Resume Recording" : "Pause Recording"
        case #selector(viewAsList(_:)):
            menuItem.state = services.library.viewMode == .list ? .on : .off
        case #selector(viewAsGrid(_:)):
            menuItem.state = services.library.viewMode == .grid ? .on : .off
        default: break
        }
        return true
    }

    // MARK: Main menu

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let host = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            host.submenu = m
            main.addItem(host)
        }
        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }

        let appName = "Clipboard Craft"
        let services = item("Services", nil)
        services.submenu = NSMenu()
        NSApp.servicesMenu = services.submenu
        submenu(appName, [
            item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(openSettings(_:)), ","),
            item("Pause Recording", #selector(togglePause(_:))),
            .separator(),
            services,
            .separator(),
            item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q")
        ])

        submenu("File", [
            item("New Collection…", #selector(newCollection(_:)), "n", [.command, .shift]),
            item("Import Files…", #selector(importFiles(_:)), "i", [.command, .shift]),
            .separator(),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w")
        ])

        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Delete", #selector(NSText.delete(_:)), "\u{8}"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find…", #selector(focusSearch(_:)), "f")
        ])

        submenu("View", [
            item("as List", #selector(viewAsList(_:)), "1"),
            item("as Grid", #selector(viewAsGrid(_:)), "2"),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        ])

        let windowMenuItems = [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Library", #selector(openLibrary(_:)), "0"),
            item("Quick Panel", #selector(openQuickPanel(_:)))
        ]
        submenu("Window", windowMenuItems)
        NSApp.windowsMenu = main.items.last?.submenu

        submenu("Help", [
            item("Welcome to Clipboard Craft", #selector(showWelcome(_:)))
        ])
        NSApp.helpMenu = main.items.last?.submenu
        return main
    }
}
