import AppKit
import SwiftUI

/// Creates and tracks the library and settings windows, and switches the activation
/// policy so the app shows a Dock icon only while one of them is open.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    private let services: AppServices
    private(set) var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    let settingsNav = SettingsNavigation()
    /// The last app (other than us) that was frontmost — the paste target from the library.
    private(set) var previousApp: NSRunningApplication?

    init(services: AppServices) {
        self.services = services
        super.init()
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap { $0 == .current ? nil : $0 }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app != NSRunningApplication.current else { return }
            MainActor.assumeIsolated { self?.previousApp = app }
        }
    }

    // MARK: Library

    func showMain(select id: UUID? = nil) {
        if mainWindow == nil { mainWindow = makeMainWindow() }
        if let id { services.library.reveal(id) }
        present(mainWindow!)
    }

    func toggleMain() {
        if let w = mainWindow, w.isVisible, w.isKeyWindow, NSApp.isActive { w.performClose(nil) } else { showMain() }
    }

    private func makeMainWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: MainView(library: services.library, store: services.store))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        hosting.sizingOptions = [.minSize]
        let w = NSWindow(contentViewController: hosting)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.title = "Clipboard Craft"
        w.toolbarStyle = .unified
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 1180, height: 740))
        w.center()
        w.setFrameAutosaveName("LibraryWindow")
        w.delegate = self
        w.tabbingMode = .disallowed
        return w
    }

    // MARK: Settings

    func showSettings(pane: SettingsPane? = nil) {
        if let pane { settingsNav.pane = pane }
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(nav: settingsNav, settings: services.settings, store: services.store))
            hosting.sceneBridgingOptions = [.toolbars, .title]
            hosting.sizingOptions = [.minSize]
            let w = NSWindow(contentViewController: hosting)
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.title = "Settings"
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 780, height: 560))
            w.center()
            w.setFrameAutosaveName("SettingsWindow")
            w.delegate = self
            w.tabbingMode = .disallowed
            settingsWindow = w
        }
        present(settingsWindow!)
    }

    // MARK: Activation

    private func present(_ window: NSWindow) {
        if services.quickPanel.isVisible { services.quickPanel.hide(animated: false) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let others = [self.mainWindow, self.settingsWindow].compactMap { $0 }.filter { $0 !== closing && $0.isVisible }
            if others.isEmpty {
                NSApp.setActivationPolicy(.accessory)
                // Give focus back to whatever the user was doing before.
                self.previousApp?.activate()
            }
        }
    }
}
