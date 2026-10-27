import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Bindable var library: LibraryModel
    let store: ClipStore

    var body: some View {
        List(selection: $library.sidebar) {
            Section("Library") {
                row("All Clips", "tray.full.fill", .accentColor, store.items.count).tag(SidebarItem.all)
                row("Pinned", "pin.fill", .orange, store.pinnedCount).tag(SidebarItem.pinned)
                row("Favorites", "star.fill", .yellow, store.favoriteCount).tag(SidebarItem.favorites)
            }

            Section("Types") {
                ForEach(ClipKind.allCases) { kind in
                    let n = store.count(of: kind)
                    if n > 0 || kind != .other {
                        row(kind.pluralTitle, kind.symbol, kind.tint, n).tag(SidebarItem.kind(kind))
                    }
                }
            }

            Section {
                ForEach(store.collections) { c in
                    CollectionRow(collection: c, count: store.count(inCollection: c.id), store: store, library: library)
                        .tag(SidebarItem.collection(c.id))
                }
                .onMove { store.moveCollections(from: $0, to: $1) }
            } header: {
                HStack {
                    Text("Collections")
                    Spacer()
                    Button { library.collectionEditor = CollectionEditorState() } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("New Collection")
                }
            }

            let apps = store.appSources
            if !apps.isEmpty {
                Section("Apps") {
                    ForEach(apps.prefix(12)) { app in
                        Label {
                            Text(app.name).lineLimit(1)
                        } icon: {
                            AppIconView(bundleID: app.bundleID, size: 16)
                        }
                        .badge(app.count)
                        .tag(SidebarItem.app(app.bundleID))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaBar(edge: .bottom) { StorageFooter(store: store) }
    }

    private func row(_ title: String, _ symbol: String, _ tint: Color, _ count: Int) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .badge(count)
    }
}

private struct CollectionRow: View {
    let collection: ClipCollection
    let count: Int
    let store: ClipStore
    let library: LibraryModel
    @State private var targeted = false
    @State private var confirmDelete = false

    var body: some View {
        Label {
            Text(collection.name)
        } icon: {
            Image(systemName: collection.symbol).foregroundStyle(collection.color.color)
        }
        .badge(count)
        .padding(.vertical, 1)
        .background {
            if targeted {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(collection.color.color.opacity(0.25)).padding(-4)
            }
        }
        .onDrop(of: [.clipID], isTargeted: $targeted) { providers in
            for p in providers {
                p.loadDataRepresentation(forTypeIdentifier: UTType.clipID.identifier) { data, _ in
                    guard let data, let s = String(data: data, encoding: .utf8), let id = UUID(uuidString: s) else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            // Dropping a selected clip adds the whole selection.
                            let ids = library.selection.contains(id) ? Array(library.selection) : [id]
                            store.setCollection(collection.id, member: true, for: ids)
                            store.showToast("Added to \(collection.name)", symbol: collection.symbol)
                        }
                    }
                }
            }
            return true
        }
        .contextMenu {
            Button("Edit Collection…") { library.collectionEditor = CollectionEditorState(existing: collection) }
            Divider()
            Button("Delete Collection", role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog("Delete “\(collection.name)”?", isPresented: $confirmDelete) {
            Button("Delete Collection", role: .destructive) {
                if library.sidebar == .collection(collection.id) { library.sidebar = .all }
                store.deleteCollection(collection.id)
            }
        } message: {
            Text("The clips inside it stay in your history.")
        }
    }
}

private struct StorageFooter: View {
    let store: ClipStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: AppSettings.shared.isPaused ? "pause.circle.fill" : "record.circle")
                .foregroundStyle(AppSettings.shared.isPaused ? .orange : .green)
                .symbolEffect(.pulse, options: .repeating, isActive: !AppSettings.shared.isPaused)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppSettings.shared.isPaused ? "Recording paused" : "Recording clipboard")
                    .font(.system(size: 11, weight: .medium))
                Text("\(store.items.count) clips · \(Format.bytes(store.totalBytes))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                AppSettings.shared.isPaused.toggle()
            } label: {
                Image(systemName: AppSettings.shared.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.borderless)
            .help(AppSettings.shared.isPaused ? "Resume recording" : "Pause recording")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
