import SwiftUI

struct QuickPanelView: View {
    @Bindable var model: QuickPanelModel
    let store: ClipStore
    @Bindable var settings: AppSettings

    @FocusState private var searchFocused: Bool
    @Namespace private var selectionNS
    @Namespace private var filterNS

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            searchBar(count: results.count)
            filterBar
            Divider().opacity(0.5)
            ZStack {
                if model.quickLook, let item = model.selectedItem {
                    ClipPreviewView(item: item, compact: false)
                        .padding(8)
                        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
                } else {
                    HStack(spacing: 0) {
                        resultsList(results)
                            .frame(width: settings.showPreviewInPanel ? 340 : nil)
                        if settings.showPreviewInPanel {
                            Divider().opacity(0.5)
                            previewPane
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)
            Divider().opacity(0.5)
            footer
        }
        .toastOverlay(store, bottomPadding: 52)
        .onAppear { searchFocused = true }
        .onChange(of: model.presentation) { searchFocused = true }
        .onChange(of: store.revision) { model.validateSelection() }
    }

    // MARK: Search

    private func searchBar(count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            if settings.isPaused {
                Button { settings.isPaused = false } label: {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.orange.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Clipboard recording is paused — click to resume")
            }
            HStack(spacing: 2) {
                iconButton("macwindow", help: "Open Library  ⌘O") { model.controller?.openInLibrary() }
                iconButton("gearshape", help: "Settings  ⌘,") { model.controller?.openSettings() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Filters

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(QuickFilter.allCases) { f in
                    let selected = model.filter == f
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { model.filter = f }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: f.symbol).font(.system(size: 10.5, weight: .semibold))
                            Text(f.title).font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5.5)
                        .background {
                            if selected {
                                Capsule().fill(Color.accentColor.gradient)
                                    .matchedGeometryEffect(id: "chip", in: filterNS)
                                    .shadow(color: .accentColor.opacity(0.35), radius: 6, y: 2)
                            } else {
                                Capsule().fill(.primary.opacity(0.06))
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.bottom, 12)
    }

    // MARK: Results

    @ViewBuilder
    private func resultsList(_ results: [ClipItem]) -> some View {
        if results.isEmpty {
            emptyState
        } else {
            let sections = Grouping.byDate(results, pinnedSeparately: settings.pinnedOnTop, now: Ticker.shared.now)
            let shortcutIndex = Dictionary(uniqueKeysWithValues: results.prefix(9).enumerated().map { ($1.id, $0 + 1) })
            ScrollViewReader { proxy in
                ScrollView {
                    // One flat ForEach (headers + rows) so clips that move between sections,
                    // e.g. when pinned, keep a single identity and always render fresh data.
                    LazyVStack(alignment: .leading, spacing: 1) {
                        Color.clear.frame(height: 0).id("top")
                        ForEach(PanelRow.rows(for: sections)) { entry in
                            switch entry {
                            case .header(let bucket, let isFirst):
                                Text(bucket.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, isFirst ? 2 : 10)
                                    .padding(.bottom, 4)
                            case .clip(let item):
                                row(item, shortcut: shortcutIndex[item.id])
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id.uuidString) }
                }
                .onChange(of: model.presentation) { proxy.scrollTo("top", anchor: .top) }
                .onChange(of: model.query) { proxy.scrollTo("top", anchor: .top) }
                .onChange(of: model.filter) { proxy.scrollTo("top", anchor: .top) }
            }
        }
    }

    private func row(_ item: ClipItem, shortcut: Int?) -> some View {
        let selected = model.selectedID == item.id
        return QuickRow(item: item, shortcut: shortcut, isSelected: selected)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.accentColor.opacity(0.22))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5))
                        .matchedGeometryEffect(id: "selection", in: selectionNS)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 11))
            .onTapGesture(count: 2) { model.controller?.paste(item) }
            .simultaneousGesture(TapGesture().onEnded {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) { model.selectedID = item.id }
            })
            .contextMenu { QuickRowMenu(item: item, model: model, store: store) }
            .onDrag { DragSupport.provider(for: item) }
            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: selected)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.items.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(store.items.isEmpty ? "Nothing copied yet" : "No matches")
                .font(.system(size: 15, weight: .semibold))
            Text(store.items.isEmpty ? "Copy text, images, links or files and they’ll appear here."
                                     : "Try another search, or use type:image, is:pinned, app:safari")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Preview

    @ViewBuilder
    private var previewPane: some View {
        if let item = model.selectedItem {
            VStack(spacing: 0) {
                ClipPreviewView(item: item, compact: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(item.id)
                Divider().opacity(0.5)
                ClipInfoView(item: item, compact: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tint)
                Text("\(store.items.count) clips")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            KeyHint(keys: ["↩"], label: settings.pasteDirectly ? "Paste" : "Copy")
            KeyHint(keys: ["⇧", "↩"], label: "Plain Text")
            KeyHint(keys: ["⌘", "P"], label: "Pin")
            KeyHint(keys: ["⌘", "Y"], label: "Preview")
            KeyHint(keys: ["⇥"], label: "Filter")
        }
        .padding(.horizontal, 18)
        .frame(height: 40)
    }
}

// MARK: - Row

private enum PanelRow: Identifiable {
    case header(DateBucket, isFirst: Bool)
    case clip(ClipItem)

    var id: String {
        switch self {
        case .header(let bucket, _): "header-\(bucket.title)"
        case .clip(let item): item.id.uuidString
        }
    }

    static func rows(for sections: [ClipSection]) -> [PanelRow] {
        var rows: [PanelRow] = []
        for (i, section) in sections.enumerated() {
            rows.append(.header(section.bucket, isFirst: i == 0))
            rows.append(contentsOf: section.items.map(PanelRow.clip))
        }
        return rows
    }
}

struct QuickRow: View {
    let item: ClipItem
    let shortcut: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            ClipIconView(item: item, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    if item.sourceBundleID != nil {
                        AppIconView(bundleID: item.sourceBundleID, size: 12)
                    }
                    Text(subtitle)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                if item.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: 9.5)).foregroundStyle(.orange).rotationEffect(.degrees(30))
                }
                if item.isFavorite {
                    Image(systemName: "star.fill").font(.system(size: 9.5)).foregroundStyle(.yellow)
                }
                if let shortcut {
                    KeyCap(text: "⌘\(shortcut)", prominent: isSelected)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6.5)
    }

    private var subtitle: String {
        let time = Format.shortRelative(item.updatedAt, now: Ticker.shared.now)
        var parts = [String]()
        if let app = item.sourceAppName { parts.append(app) }
        parts.append(time)
        parts.append(item.detailSummary)
        return parts.joined(separator: " · ")
    }
}

private struct QuickRowMenu: View {
    let item: ClipItem
    let model: QuickPanelModel
    let store: ClipStore

    var body: some View {
        Button("Paste") { model.controller?.paste(item) }
        if item.kind.isTextual || item.kind == .file {
            Button("Paste as Plain Text") { model.controller?.paste(item, plainText: true) }
        }
        Button("Copy") { model.controller?.copyOnly(item) }
        Divider()
        Button(item.isPinned ? "Unpin" : "Pin") { store.togglePin([item.id]) }
        Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite([item.id]) }
        Menu("Collections") {
            ForEach(store.collections) { c in
                Toggle(c.name, isOn: Binding(
                    get: { item.collectionIDs.contains(c.id) },
                    set: { store.setCollection(c.id, member: $0, for: [item.id]) }
                ))
            }
        }
        Divider()
        Button("Show in Library") { model.controller?.openInLibrary(item) }
        Divider()
        Button("Delete", role: .destructive) { model.controller?.delete(item) }
    }
}
