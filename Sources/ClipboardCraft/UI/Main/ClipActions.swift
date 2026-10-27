import SwiftUI

/// Actions shared by the library list, grid, inspector and menus.
@MainActor
struct ClipActions {
    let store: ClipStore
    var paste: PasteService { AppServices.shared.paste }

    func copy(_ ids: [UUID], plainText: Bool = false) {
        let items = store.items(ids)
        guard !items.isEmpty else { return }
        paste.copy(items, plainText: plainText)
        store.showToast(items.count == 1 ? "Copied to clipboard" : "Copied \(items.count) items", symbol: "doc.on.clipboard.fill")
    }

    func pasteToPreviousApp(_ ids: [UUID], plainText: Bool = false) {
        let items = store.items(ids)
        guard !items.isEmpty else { return }
        let target = AppServices.shared.windows.previousApp
        NSApp.hide(nil)
        paste.paste(items, plainText: plainText, into: target)
    }

    func delete(_ ids: [UUID], undoManager: UndoManager?) {
        guard !ids.isEmpty else { return }
        store.delete(ids)
        undoManager?.registerUndo(withTarget: store) { s in
            MainActor.assumeIsolated { s.restore(ids) }
        }
        undoManager?.setActionName(ids.count == 1 ? "Delete Clip" : "Delete Clips")
    }

    func open(_ item: ClipItem) {
        switch item.kind {
        case .link:
            if let s = item.meta.url, let url = URL(string: s) { NSWorkspace.shared.open(url) }
        case .image:
            if let f = item.meta.imageFile { NSWorkspace.shared.open(BlobStore.shared.url(for: item.id, relative: f)) }
        case .file:
            paste.fileURLs(for: item).forEach { NSWorkspace.shared.open($0) }
        default:
            break
        }
    }

    func reveal(_ item: ClipItem) {
        let urls = item.kind == .file ? paste.fileURLs(for: item)
            : item.meta.imageFile.map { [BlobStore.shared.url(for: item.id, relative: $0)] } ?? []
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}

/// Context menu for one or more selected clips.
struct ClipActionsMenu: View {
    let ids: [UUID]
    let store: ClipStore
    let library: LibraryModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let items = store.items(ids)
        let actions = ClipActions(store: store)
        if !items.isEmpty {
            Button(items.count == 1 ? "Copy" : "Copy \(items.count) Items") { actions.copy(ids) }
            if items.contains(where: { $0.kind.isTextual || $0.kind == .file }) {
                Button("Copy as Plain Text") { actions.copy(ids, plainText: true) }
            }
            if let app = AppServices.shared.windows.previousApp?.localizedName {
                Button("Paste to \(app)") { actions.pasteToPreviousApp(ids) }
            }
            Divider()
            let allPinned = items.allSatisfy(\.isPinned)
            Button(allPinned ? "Unpin" : "Pin") { store.setPinned(ids, !allPinned) }
            let allFav = items.allSatisfy(\.isFavorite)
            Button(allFav ? "Remove from Favorites" : "Add to Favorites") { store.setFavorite(ids, !allFav) }
            Menu("Collections") {
                ForEach(store.collections) { c in
                    let member = items.allSatisfy { $0.collectionIDs.contains(c.id) }
                    Button {
                        store.setCollection(c.id, member: !member, for: ids)
                    } label: {
                        if member { Label(c.name, systemImage: "checkmark") } else { Text(c.name) }
                    }
                }
                Divider()
                Button("New Collection…") { library.collectionEditor = CollectionEditorState(existing: nil, addingItems: ids) }
            }
            if items.count == 1, let item = items.first {
                if item.kind.isTextual, item.kind != .color {
                    Menu("Treat As") {
                        Button("Text") { store.setKind(ids, to: .text) }.disabled(item.kind == .text)
                        Button("Code") { store.setKind(ids, to: .code) }.disabled(item.kind == .code)
                    }
                }
                Divider()
                switch item.kind {
                case .link: Button("Open Link") { actions.open(item) }
                case .image:
                    Button("Open in Preview") { actions.open(item) }
                    Button("Show in Finder") { actions.reveal(item) }
                case .file:
                    Button("Open") { actions.open(item) }
                    Button("Show in Finder") { actions.reveal(item) }
                default: EmptyView()
                }
                if item.kind.isTextual { Button("Edit Text") { library.editingItemID = item.id; library.selection = [item.id] } }
            }
            Button("Export…") { Exporter.export(items, paste: AppServices.shared.paste) }
            Divider()
            Button("Delete", role: .destructive) { actions.delete(ids, undoManager: undoManager) }
        }
    }
}
