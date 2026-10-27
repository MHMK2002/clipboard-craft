import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Lazily converts a stored image to TIFF when an app asks for it.
private final class LazyImageProvider: NSObject, NSPasteboardItemDataProvider {
    let url: URL
    init(url: URL) { self.url = url }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff, let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation else { return }
        item.setData(tiff, forType: .tiff)
    }
}

@MainActor
final class PasteService {
    private let store: ClipStore
    private let monitor: ClipboardMonitor
    private let blobs = BlobStore.shared
    private var providers: [AnyObject] = []

    init(store: ClipStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    // MARK: Writing

    /// Places one or more clips on the general pasteboard.
    func copy(_ items: [ClipItem], plainText: Bool = false) {
        guard !items.isEmpty else { return }
        providers.removeAll()

        var pbItems: [NSPasteboardItem]
        if items.count > 1 {
            // Several clips: files are pasted together, everything else as joined text.
            if items.allSatisfy({ $0.kind == .file }) && !plainText {
                pbItems = items.flatMap { fileItems(for: $0) }
            } else {
                pbItems = [stringItem(items.compactMap { textValue(of: $0) }.joined(separator: "\n"))]
            }
        } else {
            pbItems = makeItems(for: items[0], plainText: plainText)
        }
        if pbItems.isEmpty { pbItems = [stringItem(items[0].title)] }
        pbItems[0].setData(Data(), forType: NSPasteboard.PasteboardType(PBType.own))

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(pbItems)
        monitor.skipCurrentChange()
        if AppSettings.shared.moveToTopOnPaste { items.forEach { store.bump($0.id) } }
    }

    func copyString(_ string: String) {
        let item = stringItem(string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType(PBType.own))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item])
        monitor.skipCurrentChange()
    }

    private func stringItem(_ string: String) -> NSPasteboardItem {
        let p = NSPasteboardItem()
        p.setString(string, forType: .string)
        return p
    }

    private func fileItems(for item: ClipItem) -> [NSPasteboardItem] {
        fileURLs(for: item).map { url in
            let p = NSPasteboardItem()
            p.setString(url.absoluteString, forType: .fileURL)
            p.setString(url.lastPathComponent, forType: .string)
            return p
        }
    }

    private func makeItems(for item: ClipItem, plainText: Bool) -> [NSPasteboardItem] {
        if plainText, let text = textValue(of: item) { return [stringItem(text)] }
        if item.kind == .file { return fileItems(for: item) }

        let reps = blobs.loadReps(for: item.id)
        guard !reps.isEmpty else { return item.text.map { [stringItem($0)] } ?? [] }
        var pbItems: [NSPasteboardItem] = []
        for entries in reps {
            let p = NSPasteboardItem()
            for rep in entries { p.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type)) }
            if item.kind == .image, !entries.contains(where: { $0.type == PBType.tiff }), let file = item.meta.imageFile {
                let provider = LazyImageProvider(url: blobs.url(for: item.id, relative: file))
                p.setDataProvider(provider, forTypes: [.tiff])
                providers.append(provider)
            }
            pbItems.append(p)
        }
        // If the text was edited, make sure the edited string wins.
        if item.meta.edited == true, let text = item.text { pbItems[0].setString(text, forType: .string) }
        return pbItems
    }

    /// The best plain-text value for a clip.
    func textValue(of item: ClipItem) -> String? {
        switch item.kind {
        case .file: return item.files.map(\.originalPath).joined(separator: "\n")
        case .image: return nil
        case .link: return item.meta.url ?? item.text
        default: return item.text
        }
    }

    /// File URLs to paste: the original when it still exists, otherwise the archived copy.
    func fileURLs(for item: ClipItem) -> [URL] {
        item.files.compactMap { resolvedURL(for: $0, in: item) }
    }

    func resolvedURL(for file: FileEntry, in item: ClipItem) -> URL? {
        if file.originalExists { return file.originalURL }
        if let stored = file.storedPath {
            let url = blobs.url(for: item.id, relative: stored)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    // MARK: Pasting

    var hasAccessibilityAccess: Bool { AXIsProcessTrusted() }

    func requestAccessibilityAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Some macOS versions only pick up a new Accessibility grant after the app restarts.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.8; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Copies the clip(s) and – if allowed – sends ⌘V to the frontmost app.
    func paste(_ items: [ClipItem], plainText: Bool = false, into app: NSRunningApplication?) {
        copy(items, plainText: plainText)
        guard AppSettings.shared.pasteDirectly else {
            store.showToast("Copied to clipboard", symbol: "doc.on.clipboard.fill")
            return
        }
        guard hasAccessibilityAccess else {
            requestAccessibilityAccess()
            store.showToast("Copied — allow Accessibility access to paste directly", symbol: "hand.raised.fill")
            return
        }
        var delay = 0.08
        if let app, app != NSRunningApplication.current, !app.isActive {
            app.activate()
            delay = 0.3 // give the target app time to come forward
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Self.postCommandV()
        }
    }

    private static func postCommandV() {
        let keyCode = CGKeyCode(KeyboardLayout.keyCode(for: "v") ?? UInt16(kVK_ANSI_V))
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                           state: .eventSuppressionStateSuppressionInterval)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
