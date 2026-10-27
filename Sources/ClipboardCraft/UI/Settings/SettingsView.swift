import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcuts, history, storage, privacy, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .history: "History"
        case .storage: "Storage"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .shortcuts: "keyboard.fill"
        case .history: "clock.arrow.circlepath"
        case .storage: "internaldrive.fill"
        case .privacy: "hand.raised.fill"
        case .about: "info.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .general: .gray
        case .shortcuts: .purple
        case .history: .blue
        case .storage: .teal
        case .privacy: .orange
        case .about: .indigo
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    var pane: SettingsPane? = .general
}

struct SettingsView: View {
    @Bindable var nav: SettingsNavigation
    @Bindable var settings: AppSettings
    let store: ClipStore

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.pane) {
                ForEach(SettingsPane.allCases) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            Group {
                switch nav.pane ?? .general {
                case .general: GeneralPane(settings: settings)
                case .shortcuts: ShortcutsPane(settings: settings)
                case .history: HistoryPane(settings: settings, store: store)
                case .storage: StoragePane(store: store)
                case .privacy: PrivacyPane(settings: settings)
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((nav.pane ?? .general).title)
        }
        .frame(minWidth: 720, minHeight: 500)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var hasAccess = AppServices.shared.paste.hasAccessibilityAccess
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text("Clipboard Craft lives in the menu bar and records quietly in the background.")
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Pasting") {
                Toggle("Paste directly into the active app", isOn: $settings.pasteDirectly)
                if settings.pasteDirectly {
                    HStack(spacing: 10) {
                        Image(systemName: hasAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hasAccess ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hasAccess ? "Accessibility access granted" : "Accessibility access required")
                            Text("Needed to send ⌘V to the app you’re working in.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !hasAccess {
                            Button("Open Settings…") {
                                AppServices.shared.paste.requestAccessibilityAccess()
                                AppServices.shared.paste.openAccessibilitySettings()
                            }
                            Button("Restart App") { AppServices.shared.paste.relaunch() }
                                .help("Already enabled it? Restart so macOS applies the permission.")
                        }
                    }
                }
                Toggle("Move pasted clips to the top", isOn: $settings.moveToTopOnPaste)
            }

            Section("Quick Panel") {
                Picker("Position", selection: $settings.panelPosition) {
                    ForEach(PanelPosition.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show preview pane", isOn: $settings.showPreviewInPanel)
                Toggle("Keep pinned clips at the top", isOn: $settings.pinnedOnTop)
            }
        }
        .onReceive(timer) { _ in hasAccess = AppServices.shared.paste.hasAccessibilityAccess }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(Array(settings.quickPanelShortcuts.enumerated()), id: \.element) { index, shortcut in
                    LabeledContent(index == 0 ? "Open Quick Panel" : "") {
                        HStack(spacing: 8) {
                            ShortcutStatus(shortcut: shortcut)
                            ShortcutRecorder(shortcut: Binding(
                                get: { shortcut },
                                set: { new in
                                    var list = settings.quickPanelShortcuts
                                    guard let i = list.firstIndex(of: shortcut) else { return }
                                    if let new, !list.contains(new) { list[i] = new } else if new == nil { list.remove(at: i) }
                                    settings.quickPanelShortcuts = list
                                }
                            ))
                        }
                    }
                }
                LabeledContent(settings.quickPanelShortcuts.isEmpty ? "Open Quick Panel" : "") {
                    ShortcutRecorder(shortcut: Binding(
                        get: { nil },
                        set: { new in
                            if let new, !settings.quickPanelShortcuts.contains(new) { settings.quickPanelShortcuts.append(new) }
                        }
                    ), placeholder: "Add Shortcut…", showsClear: false)
                }
            } header: {
                Text("Quick Panel")
            } footer: {
                Text("Any of these opens the quick panel. Click one to change it, press ⌫ while recording to remove it, ⎋ to cancel.")
            }

            Section {
                LabeledContent("Open Library") {
                    HStack(spacing: 8) {
                        if let s = settings.mainWindowShortcut { ShortcutStatus(shortcut: s) }
                        ShortcutRecorder(shortcut: $settings.mainWindowShortcut)
                    }
                }
            } header: {
                Text("Library Window")
            }

            Section("In the Quick Panel") {
                shortcutRow(["↑", "↓"], "Move selection")
                shortcutRow(["↩"], "Paste selected clip")
                shortcutRow(["⇧", "↩"], "Paste as plain text")
                shortcutRow(["⌘", "↩"], "Copy without pasting")
                shortcutRow(["⌘", "1…9"], "Paste clip by position")
                shortcutRow(["⇥"], "Next filter (⇧⇥ previous)")
                shortcutRow(["⌘", "Y"], "Toggle large preview")
                shortcutRow(["⌘", "P"], "Pin / unpin")
                shortcutRow(["⌘", "S"], "Favorite / unfavorite")
                shortcutRow(["⌘", "⌫"], "Delete clip")
                shortcutRow(["⌘", "Z"], "Undo delete")
                shortcutRow(["⌘", "O"], "Show in Library")
                shortcutRow(["⎋"], "Clear search / close")
            }

            Section("Search Tokens") {
                tokenRow("type:image", "Only images (also text, link, code, color, file, rich)")
                tokenRow("is:pinned", "Only pinned clips (is:fav for favorites)")
                tokenRow("app:safari", "Clips copied from an app")
                tokenRow("in:work", "Clips in a collection")
            }
        }
    }

    private func shortcutRow(_ keys: [String], _ label: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 3) { ForEach(keys, id: \.self) { KeyCap(text: $0, prominent: true) } }
        }
    }

    private func tokenRow(_ token: String, _ label: String) -> some View {
        HStack {
            Text(token).font(.system(.body, design: .monospaced)).foregroundStyle(.tint)
            Spacer()
            Text(label).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }
}

/// Warns when macOS couldn't register a shortcut (another app already uses it).
private struct ShortcutStatus: View {
    let shortcut: Shortcut
    var body: some View {
        if HotKeyCenter.shared.failed.contains(shortcut) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("This shortcut is already used by another app or the system.")
        }
    }
}

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    var placeholder = "Not set"
    var showsClear = true
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                HStack(spacing: 3) {
                    if recording {
                        Text("Type shortcut…").foregroundStyle(.tint)
                    } else if let shortcut {
                        ForEach(Array(shortcut.keyCaps.enumerated()), id: \.offset) { _, k in KeyCap(text: k, prominent: true) }
                    } else {
                        Text(placeholder).foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 110, minHeight: 22)
                .padding(.horizontal, 6)
            }
            .buttonStyle(.glass)
            if showsClear, shortcut != nil, !recording {
                Button { shortcut = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
                    .help("Clear shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            if event.keyCode == 51, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                shortcut = nil; stop(); return nil
            }
            if let s = Shortcut(event: event) { shortcut = s; stop() } else { NSSound.beep() }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { HotKeyCenter.shared.resume() }
        recording = false
    }
}

// MARK: - History

private struct HistoryPane: View {
    @Bindable var settings: AppSettings
    let store: ClipStore

    var body: some View {
        Form {
            Section {
                Picker("Keep clips for", selection: $settings.retention) {
                    ForEach(RetentionPeriod.allCases) { Text($0.title).tag($0) }
                }
                Picker("Maximum number of clips", selection: $settings.maxItems) {
                    ForEach([200, 500, 1000, 2000, 5000, 10000, 0], id: \.self) { n in
                        Text(n == 0 ? "Unlimited" : n.formatted()).tag(n)
                    }
                }
                Picker("Maximum storage", selection: $settings.maxStorageMB) {
                    ForEach([256, 512, 1024, 2048, 5120, 10240, 0], id: \.self) { mb in
                        Text(mb == 0 ? "Unlimited" : Format.megabytes(mb)).tag(mb)
                    }
                }
            } header: {
                Text("Automatic Clean-up")
            } footer: {
                Text("Pinned clips, favorites and clips in collections are never removed automatically.")
            }

            Section("Duplicates") {
                Picker("When the same content is copied again", selection: $settings.duplicateBehavior) {
                    ForEach(DuplicateBehavior.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                Toggle("Save a copy of copied files", isOn: $settings.saveFileCopies)
                Picker("Up to", selection: $settings.maxFileCopyMB) {
                    ForEach([25, 100, 200, 500, 1024, 4096], id: \.self) { mb in
                        Text(Format.megabytes(mb) + " per copy").tag(mb)
                    }
                }
                .disabled(!settings.saveFileCopies)
            } header: {
                Text("Files")
            } footer: {
                Text("Saved copies let you paste files again even after the original was moved or deleted. On APFS, copies are cloned and take almost no extra space until the original changes.")
            }
        }
        .onChange(of: settings.retention) { store.runMaintenance() }
        .onChange(of: settings.maxItems) { store.runMaintenance() }
        .onChange(of: settings.maxStorageMB) { store.runMaintenance() }
    }
}

// MARK: - Storage

private struct StorageCategory: Identifiable {
    let id: String
    let title: String
    let kinds: [ClipKind]
    let light: Color
    let dark: Color
}

/// Categorical colours in fixed order (reference data-viz palette, slots 1–4), stepped per appearance.
private let storageCategories: [StorageCategory] = [
    StorageCategory(id: "images", title: "Images", kinds: [.image], light: Color(hex: 0x2A78D6), dark: Color(hex: 0x3987E5)),
    StorageCategory(id: "files", title: "Files", kinds: [.file], light: Color(hex: 0xEB6834), dark: Color(hex: 0xD95926)),
    StorageCategory(id: "text", title: "Text, Links & Code", kinds: [.text, .richText, .link, .code, .color], light: Color(hex: 0x1BAF7A), dark: Color(hex: 0x199E70)),
    StorageCategory(id: "other", title: "Other", kinds: [.other], light: Color(hex: 0xEDA100), dark: Color(hex: 0xC98500))
]

private struct StoragePane: View {
    let store: ClipStore
    @State private var diskUsage: Int64?
    @State private var confirmClear = false
    @State private var keepProtected = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let values = storageCategories.map { cat in (cat, cat.kinds.reduce(Int64(0)) { $0 + store.bytes(of: $1) }) }
        let total = max(values.reduce(Int64(0)) { $0 + $1.1 }, 1)
        let limit = AppSettings.shared.maxStorageBytes
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.bytes(diskUsage ?? store.totalBytes))
                            .font(.system(size: 30, weight: .semibold))
                        Text(limit != nil ? "of \(Format.megabytes(AppSettings.shared.maxStorageMB)) limit" : "used · no limit")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(store.items.count) clips").foregroundStyle(.secondary)
                    }
                    StorageMeter(values: values, total: total, scheme: scheme)
                        .frame(height: 14)
                    // Legend (also the table view: every value is printed).
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        ForEach(values, id: \.0.id) { cat, bytes in
                            GridRow {
                                RoundedRectangle(cornerRadius: 3).fill(scheme == .dark ? cat.dark : cat.light).frame(width: 10, height: 10)
                                Text(cat.title)
                                Text(Format.bytes(bytes)).foregroundStyle(.secondary).monospacedDigit()
                                    .gridColumnAlignment(.trailing)
                            }
                        }
                    }
                    .font(.system(size: 12))
                }
                .padding(.vertical, 6)
            } header: {
                Text("Disk Usage")
            }

            Section {
                LabeledContent("Library location") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.dataFolder]) }
                }
                LabeledContent("Apply clean-up rules now") {
                    Button("Clean Up") {
                        store.runMaintenance()
                        store.purgeTrash()
                        recompute()
                        store.showToast("Clean-up finished", symbol: "sparkles")
                    }
                }
            }

            Section {
                Toggle("Keep pinned, favorite and collection clips", isOn: $keepProtected)
                HStack {
                    Spacer()
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                }
            } header: {
                Text("Clear History")
            }
        }
        .task { recompute() }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) {
                store.clearHistory(keepProtected: keepProtected)
                recompute()
            }
        } message: {
            Text(keepProtected ? "All clips except pinned, favorites and collection items will be deleted. This can’t be undone."
                               : "Every clip will be permanently deleted. This can’t be undone.")
        }
    }

    private func recompute() {
        let folder = AppPaths.dataFolder
        Task.detached(priority: .utility) {
            let size = BlobStore.directorySize(folder)
            await MainActor.run { diskUsage = size }
        }
    }
}

private struct StorageMeter: View {
    let values: [(StorageCategory, Int64)]
    let total: Int64
    let scheme: ColorScheme

    var body: some View {
        GeometryReader { geo in
            let visible = values.filter { $0.1 > 0 }
            let gap: CGFloat = 2
            let available = geo.size.width - gap * CGFloat(max(visible.count - 1, 0))
            HStack(spacing: gap) {
                if visible.isEmpty {
                    Capsule().fill(.primary.opacity(0.08))
                } else {
                    ForEach(visible, id: \.0.id) { cat, bytes in
                        let w = max(available * CGFloat(Double(bytes) / Double(total)), 3)
                        UnevenRoundedRectangle(
                            topLeadingRadius: cat.id == visible.first?.0.id ? 4 : 0,
                            bottomLeadingRadius: cat.id == visible.first?.0.id ? 4 : 0,
                            bottomTrailingRadius: cat.id == visible.last?.0.id ? 4 : 0,
                            topTrailingRadius: cat.id == visible.last?.0.id ? 4 : 0
                        )
                        .fill(scheme == .dark ? cat.dark : cat.light)
                        .frame(width: w)
                        .help("\(cat.title): \(Format.bytes(bytes))")
                    }
                }
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

// MARK: - Privacy

private struct PrivacyPane: View {
    @Bindable var settings: AppSettings
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                Toggle("Pause clipboard recording", isOn: $settings.isPaused)
                Toggle("Ignore passwords and other concealed content", isOn: $settings.respectConcealed)
            } footer: {
                Text("Password managers mark secrets as concealed; Clipboard Craft never records them when this is on.")
            }

            Section {
                if settings.ignoredBundleIDs.isEmpty {
                    Text("No ignored apps").foregroundStyle(.secondary)
                }
                ForEach(settings.ignoredBundleIDs, id: \.self) { id in
                    HStack(spacing: 10) {
                        AppIconView(bundleID: id, size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(appName(id))
                            Text(id).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            settings.ignoredBundleIDs.removeAll { $0 == id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Stop ignoring")
                    }
                }
                HStack {
                    Spacer()
                    Button("Add App…", action: addApp)
                }
            } header: {
                Text("Ignored Apps")
            } footer: {
                Text("Nothing copied while one of these apps is in front is recorded.")
            }

            Section {
                Toggle("Load link titles and icons", isOn: $settings.loadLinkPreviews)
            } header: {
                Text("Network")
            } footer: {
                Text("When on, previewing a link contacts that website to fetch its title and icon. Off by default because copied links can contain private tokens.")
            }
        }
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !settings.ignoredBundleIDs.contains(id) {
                settings.ignoredBundleIDs.append(id)
            }
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            AppIconBadge(size: 110)
            Text("Clipboard Craft").font(.system(size: 26, weight: .bold))
            Text("Your smarter clipboard companion").foregroundStyle(.secondary)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
