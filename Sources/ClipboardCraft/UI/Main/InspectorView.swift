import SwiftUI

struct InspectorView: View {
    @Bindable var library: LibraryModel
    let store: ClipStore

    var body: some View {
        let selected = store.items(library.selection)
        Group {
            if selected.count == 1, let item = selected.first {
                ClipDetailView(item: item, library: library, store: store)
                    .id(item.id)
            } else if selected.count > 1 {
                BatchView(items: selected, library: library, store: store)
            } else {
                ContentUnavailableView {
                    Label("No Clip Selected", systemImage: "doc.on.clipboard")
                } description: {
                    Text("Select a clip to preview it, or select several to act on them together.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Single clip

private struct ClipDetailView: View {
    let item: ClipItem
    @Bindable var library: LibraryModel
    let store: ClipStore
    @State private var draft = ""
    @Environment(\.undoManager) private var undoManager

    private var isEditing: Bool { library.editingItemID == item.id }

    var body: some View {
        let actions = ClipActions(store: store)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Group {
                    if isEditing {
                        TextEditor(text: $draft)
                            .font(item.kind == .code ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                    } else {
                        ClipPreviewView(item: item)
                    }
                }
                .frame(height: previewHeight)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .textBackgroundColor).opacity(isEditing ? 0.9 : 0.55),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isEditing ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: isEditing ? 1.5 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                actionBar(actions)

                collectionsSection

                VStack(alignment: .leading, spacing: 10) {
                    Text("Information").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    ClipInfoView(item: item)
                    if item.kind == .code { languagePicker }
                }
            }
            .padding(20)
        }
        .onChange(of: library.editingItemID) { _, id in if id == item.id { draft = item.text ?? "" } }
        .onAppear { if isEditing { draft = item.text ?? "" } }
    }

    private var previewHeight: CGFloat {
        switch item.kind {
        case .color: 330
        case .link: 280
        case .file: item.files.count > 1 ? 300 : 360
        default: 360
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ClipIconView(item: item, size: 46)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    KindBadge(kind: item.kind, label: item.kind == .code ? item.meta.codeLanguage : nil)
                    if let app = item.sourceAppName {
                        HStack(spacing: 4) {
                            AppIconView(bundleID: item.sourceBundleID, size: 13)
                            Text(app)
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                toggleButton(item.isPinned ? "pin.fill" : "pin", active: item.isPinned, tint: .orange,
                             help: item.isPinned ? "Unpin" : "Pin") { store.togglePin([item.id]) }
                toggleButton(item.isFavorite ? "star.fill" : "star", active: item.isFavorite, tint: .yellow,
                             help: item.isFavorite ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite([item.id]) }
            }
        }
    }

    private func toggleButton(_ symbol: String, active: Bool, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? tint : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(help)
    }

    @ViewBuilder
    private func actionBar(_ actions: ClipActions) -> some View {
        if isEditing {
            HStack {
                Button("Cancel") { library.editingItemID = nil }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    store.updateText(item.id, to: draft)
                    library.editingItemID = nil
                } label: {
                    Label("Save Changes", systemImage: "checkmark")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(draft == item.text)
            }
        } else {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { actions.copy([item.id]) } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.glassProminent)

                    if let app = AppServices.shared.windows.previousApp?.localizedName {
                        Button { actions.pasteToPreviousApp([item.id]) } label: {
                            Label("Paste", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(.glass)
                        .help("Paste into \(app)")
                    }

                    if item.kind.isTextual {
                        Button { library.editingItemID = item.id } label: { Label("Edit", systemImage: "pencil") }
                            .buttonStyle(.glass)
                    }

                    Menu {
                        if item.kind.isTextual || item.kind == .file {
                            Button("Copy as Plain Text") { actions.copy([item.id], plainText: true) }
                        }
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
                        if item.kind.isTextual, item.kind != .color {
                            Menu("Treat As") {
                                Button("Text") { store.setKind([item.id], to: .text) }.disabled(item.kind == .text)
                                Button("Code") { store.setKind([item.id], to: .code) }.disabled(item.kind == .code)
                            }
                        }
                        Button("Export…") { Exporter.export([item], paste: AppServices.shared.paste) }
                        Divider()
                        Button("Delete", role: .destructive) { actions.delete([item.id], undoManager: undoManager) }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.glass)
                    .fixedSize()

                    Spacer(minLength: 0)

                    Button(role: .destructive) { actions.delete([item.id], undoManager: undoManager) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.glass)
                    .help("Delete (⌫)")
                }
                .controlSize(.large)
            }
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collections").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(store.collections) { c in
                    let member = item.collectionIDs.contains(c.id)
                    Button {
                        withAnimation(.spring(response: 0.25)) { store.setCollection(c.id, member: !member, for: [item.id]) }
                    } label: {
                        Label(c.name, systemImage: member ? "checkmark" : c.symbol)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(member ? Color.white : c.color.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(member ? AnyShapeStyle(c.color.color.gradient) : AnyShapeStyle(c.color.color.opacity(0.13)), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button { library.collectionEditor = CollectionEditorState(existing: nil, addingItems: [item.id]) } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var languagePicker: some View {
        HStack {
            Text("Highlight as").foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { item.meta.codeLanguage ?? "Code" },
                set: { store.setCodeLanguage(item.id, $0) }
            )) {
                ForEach(CodeLanguage.all.keys.sorted(), id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
        .font(.system(size: 12))
    }
}

// MARK: - Multiple clips

private struct BatchView: View {
    let items: [ClipItem]
    @Bindable var library: LibraryModel
    let store: ClipStore
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let ids = items.map(\.id)
        let actions = ClipActions(store: store)
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                ForEach(Array(items.prefix(4).enumerated().reversed()), id: \.element.id) { i, item in
                    ClipIconView(item: item, size: 84)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        .rotationEffect(.degrees(Double(i) * 7 - 10))
                        .offset(x: CGFloat(i) * 14 - 20, y: CGFloat(i) * -4)
                }
            }
            .frame(height: 120)
            VStack(spacing: 4) {
                Text("\(items.count) Clips Selected").font(.system(size: 18, weight: .semibold))
                Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { actions.copy(ids) } label: { Label("Copy Together", systemImage: "doc.on.doc") }
                            .buttonStyle(.glassProminent)
                        Button { store.togglePin(ids) } label: { Label("Pin", systemImage: "pin") }
                            .buttonStyle(.glass)
                        Button { store.toggleFavorite(ids) } label: { Label("Favorite", systemImage: "star") }
                            .buttonStyle(.glass)
                    }
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(store.collections) { c in
                                Button(c.name) {
                                    store.setCollection(c.id, member: true, for: ids)
                                    store.showToast("Added \(ids.count) clips to \(c.name)", symbol: c.symbol)
                                }
                            }
                            Divider()
                            Button("New Collection…") { library.collectionEditor = CollectionEditorState(existing: nil, addingItems: ids) }
                        } label: {
                            Label("Add to Collection", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.glass)
                        .fixedSize()
                        Button { Exporter.export(items, paste: AppServices.shared.paste) } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.glass)
                        Button(role: .destructive) { actions.delete(ids, undoManager: undoManager) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.glass)
                    }
                }
                .controlSize(.large)
            }
            Spacer()
        }
        .padding(24)
    }

    private var summary: String {
        var counts: [ClipKind: Int] = [:]
        for i in items { counts[i.kind, default: 0] += 1 }
        let parts = ClipKind.allCases.compactMap { k in counts[k].map { "\($0) \($0 == 1 ? k.title.lowercased() : k.pluralTitle.lowercased())" } }
        let size = items.reduce(Int64(0)) { $0 + $1.byteSize }
        return parts.joined(separator: ", ") + " · " + Format.bytes(size)
    }
}

// MARK: - Flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
