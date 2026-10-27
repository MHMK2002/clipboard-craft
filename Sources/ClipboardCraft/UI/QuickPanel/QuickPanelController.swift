import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless floating panel that can take keyboard focus without activating the app,
/// so the previously active app stays frontmost and receives the paste.
final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickPanelController: NSObject, NSWindowDelegate {
    private let services: AppServices
    let model: QuickPanelModel
    private var panel: QuickPanel!
    private var glass: NSGlassEffectView!
    private var keyMonitor: Any?
    private var targetApp: NSRunningApplication?
    private var isClosing = false

    static let fullSize = NSSize(width: 820, height: 520)
    static let compactSize = NSSize(width: 560, height: 520)

    var isVisible: Bool { panel?.isVisible == true && !isClosing }

    var debugWindow: NSWindow? { panel }

    init(services: AppServices) {
        self.services = services
        self.model = QuickPanelModel(store: services.store)
        super.init()
        model.controller = self
        buildPanel()
    }

    private func buildPanel() {
        let size = currentSize
        panel = QuickPanel(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                           backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        glass = NSGlassEffectView()
        glass.cornerRadius = 28
        glass.style = .regular

        let hosting = NSHostingView(rootView: QuickPanelView(model: model, store: services.store, settings: services.settings))
        hosting.sizingOptions = []
        glass.contentView = hosting
        panel.contentView = glass
    }

    private var currentSize: NSSize { services.settings.showPreviewInPanel ? Self.fullSize : Self.compactSize }

    // MARK: Show / hide

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        targetApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        Ticker.shared.refresh()
        model.prepareForPresentation()
        isClosing = false

        let size = currentSize
        let frame = targetFrame(size: size)
        panel.setFrame(frame.offsetBy(dx: 0, dy: -10), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
    }

    func hide(animated: Bool = true) {
        guard panel.isVisible, !isClosing else { return }
        isClosing = true
        removeKeyMonitor()
        let finish = { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.isClosing = false
            self.model.quickLook = false
        }
        guard animated else { finish(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: -6), display: true)
        }, completionHandler: { MainActor.assumeIsolated { finish() } })
    }

    private func targetFrame(size: NSSize) -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        switch services.settings.panelPosition {
        case .center:
            let x = vf.midX - size.width / 2
            let y = vf.minY + vf.height * 0.58 - size.height / 2
            return NSRect(x: x, y: max(vf.minY + 20, y), width: size.width, height: size.height)
        case .mouse:
            var x = mouse.x - size.width / 2
            var y = mouse.y - size.height - 12
            x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
            if y < vf.minY + 8 { y = min(mouse.y + 12, vf.maxY - size.height - 8) }
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere else dismisses the panel (but not while a context menu is open).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow, NSApp.modalWindow == nil else { return }
            self.hide()
        }
    }

    // MARK: Actions

    func paste(_ item: ClipItem? = nil, plainText: Bool = false) {
        guard let item = item ?? model.selectedItem else { return }
        let target = targetApp
        hide(animated: false)
        services.paste.paste([item], plainText: plainText, into: target)
    }

    func copyOnly(_ item: ClipItem? = nil) {
        guard let item = item ?? model.selectedItem else { return }
        services.paste.copy([item])
        services.store.showToast("Copied to clipboard", symbol: "doc.on.clipboard.fill")
        hide()
    }

    func togglePin(_ item: ClipItem? = nil) {
        guard let item = item ?? model.selectedItem else { return }
        services.store.togglePin([item.id])
    }

    func toggleFavorite(_ item: ClipItem? = nil) {
        guard let item = item ?? model.selectedItem else { return }
        services.store.toggleFavorite([item.id])
    }

    func delete(_ item: ClipItem? = nil) {
        guard let item = item ?? model.selectedItem else { return }
        let results = model.results
        let index = results.firstIndex { $0.id == item.id } ?? 0
        services.store.delete([item.id])
        let remaining = model.results
        model.selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    func openInLibrary(_ item: ClipItem? = nil) {
        let id = (item ?? model.selectedItem)?.id
        hide(animated: false)
        services.windows.showMain(select: id)
    }

    func openSettings() {
        hide(animated: false)
        services.windows.showSettings()
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        // Let input methods finish composing first.
        if let tv = panel.firstResponder as? NSTextView, tv.hasMarkedText() { return false }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)
        let key = Int(event.keyCode)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch key {
        case kVK_Escape:
            if model.quickLook { model.quickLook = false }
            else if !model.query.isEmpty { model.query = "" }
            else { hide() }
            return true
        case kVK_DownArrow:
            cmd ? model.selectEdge(last: true) : model.moveSelection(1)
            return true
        case kVK_UpArrow:
            cmd ? model.selectEdge(last: false) : model.moveSelection(-1)
            return true
        case kVK_PageDown:
            model.moveSelection(8); return true
        case kVK_PageUp:
            model.moveSelection(-8); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if cmd { copyOnly() } else { paste(plainText: shift) }
            return true
        case kVK_Tab:
            model.cycleFilter(forward: !shift)
            return true
        case kVK_Delete, kVK_ForwardDelete:
            if cmd { delete(); return true }
            return false
        default:
            break
        }

        guard cmd else { return false }
        // Use the ASCII-layout character so shortcuts work with Persian/Arabic layouts too.
        let latin = KeyboardLayout.character(for: event.keyCode)?.lowercased() ?? chars
        if let n = Int(latin), (1...9).contains(n) {
            if let item = model.item(atShortcut: n) { paste(item, plainText: shift) }
            return true
        }
        switch latin {
        case "p": togglePin(); return true
        case "s": toggleFavorite(); return true
        case "c" where !(panel.firstResponder is NSTextView && hasSearchSelection): copyOnly(); return true
        case "y": withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.quickLook.toggle() }; return true
        case "o": openInLibrary(); return true
        case ",": openSettings(); return true
        case "z": services.store.undoLastDeletion(); model.validateSelection(); return true
        case "w": hide(); return true
        case "f":
            model.presentation += 1; return true
        default: return false
        }
    }

    private var hasSearchSelection: Bool {
        guard let tv = panel.firstResponder as? NSTextView else { return false }
        return tv.selectedRange().length > 0
    }

    /// Re-applies size changes made in Settings.
    func settingsChanged() {
        guard panel.isVisible else { return }
        let frame = targetFrame(size: currentSize)
        panel.setFrame(frame, display: true, animate: true)
    }
}
