import AppKit
import Observation

/// Owns the long-lived services of the app.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let settings = AppSettings.shared
    let store: ClipStore
    let monitor: ClipboardMonitor
    let paste: PasteService
    let library: LibraryModel
    lazy var quickPanel = QuickPanelController(services: self)
    lazy var windows = WindowManager(services: self)

    private init() {
        let db: Database
        do {
            db = try Database(url: AppPaths.databaseURL)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Clipboard Craft can’t open its library"
            alert.informativeText = "\(error)\n\n\(AppPaths.databaseURL.path)"
            alert.runModal()
            exit(1)
        }
        store = ClipStore(db: db)
        monitor = ClipboardMonitor(store: store)
        paste = PasteService(store: store, monitor: monitor)
        library = LibraryModel()
    }
}

/// Minute-resolution clock so relative timestamps refresh without per-row timers.
@MainActor
@Observable
final class Ticker {
    static let shared = Ticker()
    private(set) var now = Date()
    @ObservationIgnored private var timer: Timer?

    private init() {
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() { now = Date() }
}
