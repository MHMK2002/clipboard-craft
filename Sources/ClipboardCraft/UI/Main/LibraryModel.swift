import SwiftUI

enum SidebarItem: Hashable {
    case all, pinned, favorites
    case kind(ClipKind)
    case app(String)
    case collection(UUID)
}

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case list, grid
    var id: String { rawValue }
    var symbol: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    var title: String { self == .list ? "List" : "Grid" }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, oldest, mostUsed, largest, title
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: "Most Recent"
        case .oldest: "Oldest First"
        case .mostUsed: "Most Copied"
        case .largest: "Largest"
        case .title: "Name"
        }
    }
    /// Date sections only make sense for chronological orders.
    var isChronological: Bool { self == .recent || self == .oldest }
}

@MainActor
@Observable
final class LibraryModel {
    var sidebar: SidebarItem? = .all { didSet { if sidebar != oldValue { selection = [] } } }
    var searchText = ""
    var selection: Set<UUID> = []
    var viewMode: LibraryViewMode = LibraryViewMode(rawValue: UserDefaults.standard.string(forKey: "libraryViewMode") ?? "") ?? .list {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "libraryViewMode") }
    }
    var sort: LibrarySort = .recent
    var searchFocused = false
    var collectionEditor: CollectionEditorState?
    var showOnboarding = false
    var editingItemID: UUID?
    /// Anchor for shift-click range selection in grid mode.
    @ObservationIgnored var selectionAnchor: UUID?

    var filter: ClipFilter {
        switch sidebar ?? .all {
        case .all: .all
        case .pinned: ClipFilter(pinnedOnly: true)
        case .favorites: ClipFilter(favoritesOnly: true)
        case .kind(let k): ClipFilter(kinds: [k])
        case .app(let b): ClipFilter(appBundleID: b)
        case .collection(let c): ClipFilter(collectionID: c)
        }
    }

    func results(in store: ClipStore) -> [ClipItem] {
        let base = store.results(query: searchText, filter: filter)
        switch sort {
        case .recent: return base
        case .oldest: return base.reversed()
        case .mostUsed: return base.sorted { $0.copyCount == $1.copyCount ? $0.updatedAt > $1.updatedAt : $0.copyCount > $1.copyCount }
        case .largest: return base.sorted { $0.byteSize > $1.byteSize }
        case .title: return base.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
    }

    func title(in store: ClipStore) -> String {
        switch sidebar ?? .all {
        case .all: "All Clips"
        case .pinned: "Pinned"
        case .favorites: "Favorites"
        case .kind(let k): k.pluralTitle
        case .app(let b): store.appSources.first { $0.bundleID == b }?.name ?? "App"
        case .collection(let c): store.collection(c)?.name ?? "Collection"
        }
    }

    func reveal(_ id: UUID) {
        sidebar = .all
        searchText = ""
        selection = [id]
    }
}

struct CollectionEditorState: Identifiable {
    let id = UUID()
    var existing: ClipCollection?
    var addingItems: [UUID] = []
}
