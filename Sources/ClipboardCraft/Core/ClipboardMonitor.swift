import AppKit

/// Watches the general pasteboard and feeds new content into the capture pipeline.
@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let store: ClipStore
    private var timer: Timer?
    private var lastChangeCount: Int
    /// Change count produced by our own writes; those are never recorded.
    var ignoredChangeCount: Int = -1

    init(store: ClipStore) {
        self.store = store
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard count != ignoredChangeCount else { return }

        let settings = AppSettings.shared
        guard !settings.isPaused else { return }

        let front = NSWorkspace.shared.frontmostApplication
        if let bundle = front?.bundleIdentifier, settings.ignoredBundleIDs.contains(bundle) { return }

        guard var snapshot = PasteboardSnapshot.capture(from: pasteboard, respectPrivacy: settings.respectConcealed) else { return }
        snapshot.sourceBundleID = front?.bundleIdentifier
        snapshot.sourceAppName = front?.localizedName
        ingest(snapshot)
    }

    /// Entry point for both pasteboard captures and drag & drop imports.
    func ingest(_ snapshot: PasteboardSnapshot) {
        let s = AppSettings.shared
        CaptureProcessor.shared.process(snapshot, options: .init(
            duplicateBehavior: s.duplicateBehavior,
            saveFileCopies: s.saveFileCopies,
            maxFileCopyBytes: s.maxFileCopyBytes
        ), store: store)
    }

    /// Lets the next change (made by us) pass unrecorded.
    func skipCurrentChange() {
        ignoredChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
    }
}
