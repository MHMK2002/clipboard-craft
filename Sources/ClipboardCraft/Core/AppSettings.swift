import AppKit
import Observation

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum DuplicateBehavior: String, CaseIterable, Identifiable {
    case moveToTop, keepBoth, ignore
    var id: String { rawValue }
    var title: String {
        switch self {
        case .moveToTop: "Move existing item to top"
        case .keepBoth: "Keep every copy"
        case .ignore: "Ignore the new copy"
        }
    }
}

enum PanelPosition: String, CaseIterable, Identifiable {
    case center, mouse
    var id: String { rawValue }
    var title: String {
        switch self {
        case .center: "Center of screen"
        case .mouse: "Near mouse pointer"
        }
    }
}

enum RetentionPeriod: Int, CaseIterable, Identifiable {
    case day = 1, week = 7, month = 30, quarter = 90, year = 365, forever = 0
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .day: "1 Day"
        case .week: "1 Week"
        case .month: "1 Month"
        case .quarter: "3 Months"
        case .year: "1 Year"
        case .forever: "Forever"
        }
    }
    var interval: TimeInterval? { rawValue == 0 ? nil : TimeInterval(rawValue) * 86_400 }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored var onShortcutsChanged: (() -> Void)?
    @ObservationIgnored var onAppearanceChanged: (() -> Void)?

    // General
    var appearance: AppearanceMode { didSet { save(appearance.rawValue, "appearance"); onAppearanceChanged?() } }
    var pasteDirectly: Bool { didSet { save(pasteDirectly, "pasteDirectly") } }
    var moveToTopOnPaste: Bool { didSet { save(moveToTopOnPaste, "moveToTopOnPaste") } }
    var showPreviewInPanel: Bool { didSet { save(showPreviewInPanel, "showPreviewInPanel") } }
    var pinnedOnTop: Bool { didSet { save(pinnedOnTop, "pinnedOnTop") } }
    var panelPosition: PanelPosition { didSet { save(panelPosition.rawValue, "panelPosition") } }
    var playSound: Bool { didSet { save(playSound, "playSound") } }

    // Shortcuts
    /// Every shortcut that opens the quick panel (any of them works).
    var quickPanelShortcuts: [Shortcut] { didSet { saveShortcuts(quickPanelShortcuts, "quickPanelShortcuts"); onShortcutsChanged?() } }
    var mainWindowShortcut: Shortcut? { didSet { saveShortcut(mainWindowShortcut, "mainWindowShortcut"); onShortcutsChanged?() } }

    // History
    var retention: RetentionPeriod { didSet { save(retention.rawValue, "retention") } }
    var maxItems: Int { didSet { save(maxItems, "maxItems") } }
    var maxStorageMB: Int { didSet { save(maxStorageMB, "maxStorageMB") } }
    var duplicateBehavior: DuplicateBehavior { didSet { save(duplicateBehavior.rawValue, "duplicateBehavior") } }
    var saveFileCopies: Bool { didSet { save(saveFileCopies, "saveFileCopies") } }
    var maxFileCopyMB: Int { didSet { save(maxFileCopyMB, "maxFileCopyMB") } }

    // Privacy
    var isPaused: Bool { didSet { save(isPaused, "isPaused") } }
    var respectConcealed: Bool { didSet { save(respectConcealed, "respectConcealed") } }
    var ignoredBundleIDs: [String] { didSet { save(ignoredBundleIDs, "ignoredBundleIDs") } }
    var loadLinkPreviews: Bool { didSet { save(loadLinkPreviews, "loadLinkPreviews") } }

    // Onboarding
    var hasCompletedOnboarding: Bool { didSet { save(hasCompletedOnboarding, "hasCompletedOnboarding") } }

    static let defaultIgnoredApps = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.lastpass.LastPass",
        "in.sinew.Enpass-Desktop"
    ]

    private init() {
        let d = UserDefaults.standard
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        pasteDirectly = d.object(forKey: "pasteDirectly") as? Bool ?? true
        moveToTopOnPaste = d.object(forKey: "moveToTopOnPaste") as? Bool ?? true
        showPreviewInPanel = d.object(forKey: "showPreviewInPanel") as? Bool ?? true
        pinnedOnTop = d.object(forKey: "pinnedOnTop") as? Bool ?? true
        panelPosition = PanelPosition(rawValue: d.string(forKey: "panelPosition") ?? "") ?? .center
        playSound = d.object(forKey: "playSound") as? Bool ?? false

        quickPanelShortcuts = Self.loadShortcuts("quickPanelShortcuts", default: [.defaultQuickPanel])
        mainWindowShortcut = Self.loadShortcut("mainWindowShortcut", default: .defaultMainWindow)

        retention = RetentionPeriod(rawValue: d.object(forKey: "retention") as? Int ?? 30) ?? .month
        maxItems = d.object(forKey: "maxItems") as? Int ?? 2000
        maxStorageMB = d.object(forKey: "maxStorageMB") as? Int ?? 2048
        duplicateBehavior = DuplicateBehavior(rawValue: d.string(forKey: "duplicateBehavior") ?? "") ?? .moveToTop
        saveFileCopies = d.object(forKey: "saveFileCopies") as? Bool ?? true
        maxFileCopyMB = d.object(forKey: "maxFileCopyMB") as? Int ?? 200

        isPaused = d.object(forKey: "isPaused") as? Bool ?? false
        respectConcealed = d.object(forKey: "respectConcealed") as? Bool ?? true
        ignoredBundleIDs = d.stringArray(forKey: "ignoredBundleIDs") ?? Self.defaultIgnoredApps
        loadLinkPreviews = d.object(forKey: "loadLinkPreviews") as? Bool ?? false

        hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")
    }

    var maxStorageBytes: Int64? { maxStorageMB <= 0 ? nil : Int64(maxStorageMB) * 1_048_576 }
    var maxFileCopyBytes: Int64 { Int64(maxFileCopyMB) * 1_048_576 }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private func saveShortcut(_ s: Shortcut?, _ key: String) {
        if let s, let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: key)
        } else {
            // Store an explicit "none" so the default isn't restored on next launch.
            defaults.set(Data(), forKey: key)
        }
    }

    private func saveShortcuts(_ list: [Shortcut], _ key: String) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: key) }
    }

    private static func loadShortcuts(_ key: String, default def: [Shortcut]) -> [Shortcut] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return def }
        return (try? JSONDecoder().decode([Shortcut].self, from: data)) ?? def
    }

    private static func loadShortcut(_ key: String, default def: Shortcut?) -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return def }
        if data.isEmpty { return nil }
        return (try? JSONDecoder().decode(Shortcut.self, from: data)) ?? def
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
