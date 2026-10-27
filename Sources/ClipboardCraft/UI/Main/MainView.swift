import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var library: LibraryModel
    let store: ClipStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(library: library, store: store)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } content: {
            ContentColumn(library: library, store: store)
                .navigationSplitViewColumnWidth(min: 340, ideal: 440)
        } detail: {
            InspectorView(library: library, store: store)
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        }
        .searchable(text: $library.searchText, placement: .toolbar, prompt: "Search clips")
        .searchFocused($searchFocused)
        .onChange(of: library.searchFocused) { _, v in if v { searchFocused = true; library.searchFocused = false } }
        .toastOverlay(store)
        .sheet(item: $library.collectionEditor) { state in
            CollectionEditorView(state: state, store: store, library: library)
        }
        .sheet(isPresented: $library.showOnboarding) {
            OnboardingView { library.showOnboarding = false }
        }
        .frame(minWidth: 900, minHeight: 520)
    }
}

// MARK: - Content column

private struct ContentColumn: View {
    @Bindable var library: LibraryModel
    let store: ClipStore
    @State private var dropTargeted = false

    var body: some View {
        let results = library.results(in: store)
        Group {
            if results.isEmpty {
                emptyState
            } else if library.viewMode == .list {
                ClipListView(results: results, library: library, store: store)
            } else {
                ClipGridView(results: results, library: library, store: store)
            }
        }
        .navigationTitle(library.title(in: store))
        .navigationSubtitle(results.count == 1 ? "1 clip" : "\(results.count) clips")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("View", selection: $library.viewMode) {
                    ForEach(LibraryViewMode.allCases) { m in
                        Label(m.title, systemImage: m.symbol).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .help("View as list or grid")

                Menu {
                    Picker("Sort By", selection: $library.sort) {
                        ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort clips")

                Button { Importer.chooseFilesToImport() } label: {
                    Label("Import", systemImage: "plus")
                }
                .help("Import files into the library")
            }
        }
        .onDrop(of: Importer.dropTypes, isTargeted: $dropTargeted) { providers in
            Importer.handleDrop(providers)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        Label("Drop to add to Clipboard Craft", systemImage: "square.and.arrow.down.on.square")
                            .font(.headline)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .glassEffect(.regular, in: Capsule())
                    }
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
    }

    @ViewBuilder private var emptyState: some View {
        if store.items.isEmpty {
            ContentUnavailableView {
                Label("Your clipboard history is empty", systemImage: "doc.on.clipboard")
            } description: {
                Text("Copy something anywhere on your Mac, or drop files and images here.\nPress \(AppSettings.shared.quickPanelShortcuts.first?.displayString ?? "your shortcut") to open the quick panel.")
            }
        } else if !library.searchText.isEmpty {
            ContentUnavailableView.search(text: library.searchText)
        } else {
            ContentUnavailableView("No Clips", systemImage: "tray", description: Text("Nothing here yet."))
        }
    }
}

// MARK: - List

private struct ClipListView: View {
    let results: [ClipItem]
    @Bindable var library: LibraryModel
    let store: ClipStore
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let actions = ClipActions(store: store)
        List(selection: $library.selection) {
            if library.sort.isChronological {
                ForEach(Grouping.byDate(results, pinnedSeparately: false, now: Ticker.shared.now)) { section in
                    Section(section.bucket.title) {
                        ForEach(section.items) { item in rowView(item) }
                    }
                }
            } else {
                ForEach(results) { item in rowView(item) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: UUID.self) { ids in
            ClipActionsMenu(ids: Array(ids), store: store, library: library)
        } primaryAction: { ids in
            actions.copy(Array(ids))
        }
        .onDeleteCommand { actions.delete(Array(library.selection), undoManager: undoManager) }
        .onCopyCommand {
            let ids = Array(library.selection)
            DispatchQueue.main.async { actions.copy(ids) }
            return []
        }
    }

    private func rowView(_ item: ClipItem) -> some View {
        LibraryRow(item: item, store: store)
            .tag(item.id)
            .onDrag { DragSupport.provider(for: item) }
    }
}

struct LibraryRow: View {
    let item: ClipItem
    let store: ClipStore

    var body: some View {
        HStack(spacing: 12) {
            ClipIconView(item: item, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if item.sourceBundleID != nil { AppIconView(bundleID: item.sourceBundleID, size: 12) }
                    Text([item.sourceAppName, Format.shortRelative(item.updatedAt, now: Ticker.shared.now), item.detailSummary]
                        .compactMap { $0 }.joined(separator: " · "))
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            HStack(spacing: 5) {
                ForEach(store.collections.filter { item.collectionIDs.contains($0.id) }) { CollectionDot(collection: $0) }
                if item.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.orange).rotationEffect(.degrees(30))
                }
                if item.isFavorite {
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Grid

private struct ClipGridView: View {
    let results: [ClipItem]
    @Bindable var library: LibraryModel
    let store: ClipStore
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let actions = ClipActions(store: store)
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165, maximum: 320), spacing: 14)], spacing: 14) {
                ForEach(results) { item in
                    ClipCard(item: item, store: store, isSelected: library.selection.contains(item.id))
                        .onTapGesture(count: 2) { actions.copy([item.id]) }
                        .simultaneousGesture(TapGesture().onEnded { select(item) })
                        .contextMenu {
                            ClipActionsMenu(ids: library.selection.contains(item.id) ? Array(library.selection) : [item.id],
                                            store: store, library: library)
                        }
                        .onDrag { DragSupport.provider(for: item) }
                }
            }
            .padding(16)
        }
        .background {
            Color.clear.contentShape(Rectangle()).onTapGesture { library.selection = [] }
        }
        .focusable()
        .focusEffectDisabled()
        .onDeleteCommand { actions.delete(Array(library.selection), undoManager: undoManager) }
        .onCopyCommand {
            let ids = Array(library.selection)
            DispatchQueue.main.async { actions.copy(ids) }
            return []
        }
        .onKeyPress(.return) {
            actions.copy(Array(library.selection)); return .handled
        }
    }

    private func select(_ item: ClipItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if library.selection.contains(item.id) { library.selection.remove(item.id) } else { library.selection.insert(item.id) }
            library.selectionAnchor = item.id
        } else if flags.contains(.shift), let anchor = library.selectionAnchor,
                  let a = results.firstIndex(where: { $0.id == anchor }), let b = results.firstIndex(where: { $0.id == item.id }) {
            library.selection = Set(results[min(a, b)...max(a, b)].map(\.id))
        } else {
            library.selection = [item.id]
            library.selectionAnchor = item.id
        }
    }
}

private struct ClipCard: View {
    let item: ClipItem
    let store: ClipStore
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            CardPreview(item: item)
                .frame(height: 128)
                .frame(maxWidth: .infinity)
                .clipped()
            Divider().opacity(0.6)
            HStack(spacing: 8) {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.kind.tint)
                    .frame(width: 22, height: 22)
                    .background(item.kind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(Format.shortRelative(item.updatedAt, now: Ticker.shared.now) + " · " + item.detailSummary)
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if item.isPinned { Image(systemName: "pin.fill").font(.system(size: 9.5)).foregroundStyle(.orange) }
                if item.isFavorite { Image(systemName: "star.fill").font(.system(size: 9.5)).foregroundStyle(.yellow) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(hovering ? 0.18 : 0.08),
                              lineWidth: isSelected ? 2.5 : 1)
        }
        .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .black.opacity(hovering ? 0.1 : 0.04),
                radius: isSelected ? 10 : 6, y: 3)
        .scaleEffect(hovering && !isSelected ? 1.015 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct CardPreview: View {
    let item: ClipItem
    @State private var image: NSImage?

    var body: some View {
        switch item.kind {
        case .image, .file:
            ZStack {
                if item.kind == .image { Checkerboard() }
                if let image {
                    Image(nsImage: image).resizable()
                        .aspectRatio(contentMode: item.kind == .image ? .fill : .fit)
                        .padding(item.kind == .file ? 18 : 0)
                } else {
                    ClipIconView(item: item, size: 56)
                }
            }
            .task(id: item.id) { image = await ThumbnailProvider.shared.image(for: item, size: 260) }
        case .color:
            let c = item.meta.colorHex.flatMap(ColorParser.parse)
            ZStack {
                (c?.color ?? .gray)
                Text(c?.hex ?? "").font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(c?.isLight == true ? Color.black.opacity(0.7) : .white)
            }
        case .link:
            VStack(spacing: 8) {
                ClipIconView(item: item, size: 44)
                Text(item.meta.urlHost ?? "").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(item.meta.url ?? "").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [.blue.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom))
        case .code:
            Text(String((item.text ?? "").prefix(600)))
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(9)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.purple.opacity(0.05))
        case .text, .richText:
            Text(String((item.text ?? "").prefix(600)))
                .font(.system(size: 11.5))
                .lineLimit(7)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .other:
            Image(systemName: item.kind.symbol).font(.system(size: 30)).foregroundStyle(item.kind.tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
