import SwiftUI

enum QuickFilter: String, CaseIterable, Identifiable {
    case all, pinned, text, link, image, file, code, color

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .pinned: "Pinned"
        case .text: "Text"
        case .link: "Links"
        case .image: "Images"
        case .file: "Files"
        case .code: "Code"
        case .color: "Colors"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .pinned: "pin"
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .color: "paintpalette"
        }
    }

    var filter: ClipFilter {
        switch self {
        case .all: .all
        case .pinned: ClipFilter(pinnedOnly: true)
        case .text: ClipFilter(kinds: [.text, .richText])
        case .link: ClipFilter(kinds: [.link])
        case .image: ClipFilter(kinds: [.image])
        case .file: ClipFilter(kinds: [.file])
        case .code: ClipFilter(kinds: [.code])
        case .color: ClipFilter(kinds: [.color])
        }
    }
}

@MainActor
@Observable
final class QuickPanelModel {
    var query = "" { didSet { if query != oldValue { selectFirst() } } }
    var filter: QuickFilter = .all { didSet { if filter != oldValue { selectFirst() } } }
    var selectedID: UUID?
    var quickLook = false
    /// Incremented each time the panel is shown so the view can refocus the search field.
    var presentation = 0

    @ObservationIgnored let store: ClipStore
    @ObservationIgnored let settings = AppSettings.shared
    @ObservationIgnored weak var controller: QuickPanelController?
    @ObservationIgnored private var cacheKey = ""
    @ObservationIgnored private var cache: [ClipItem] = []

    init(store: ClipStore) {
        self.store = store
    }

    var results: [ClipItem] {
        let key = "\(query)|\(filter.rawValue)|\(store.revision)|\(settings.pinnedOnTop)"
        if key == cacheKey { return cache }
        let r = store.results(query: query, filter: filter.filter, pinnedFirst: settings.pinnedOnTop)
        cacheKey = key
        cache = r
        return r
    }

    var selectedItem: ClipItem? {
        guard let id = selectedID else { return nil }
        return store.item(id)
    }

    func prepareForPresentation() {
        query = ""
        filter = .all
        quickLook = false
        selectFirst()
        presentation += 1
    }

    func selectFirst() {
        selectedID = results.first?.id
    }

    /// Keeps a valid selection when the underlying list changes.
    func validateSelection() {
        let r = results
        if let id = selectedID, r.contains(where: { $0.id == id }) { return }
        selectedID = r.first?.id
    }

    func moveSelection(_ delta: Int) {
        let r = results
        guard !r.isEmpty else { selectedID = nil; return }
        let current = selectedID.flatMap { id in r.firstIndex { $0.id == id } } ?? -1
        let next = min(max(current + delta, 0), r.count - 1)
        selectedID = r[next].id
    }

    func selectEdge(last: Bool) {
        selectedID = last ? results.last?.id : results.first?.id
    }

    func cycleFilter(forward: Bool) {
        let all = QuickFilter.allCases
        let i = all.firstIndex(of: filter) ?? 0
        filter = all[(i + (forward ? 1 : all.count - 1)) % all.count]
    }

    func item(atShortcut n: Int) -> ClipItem? {
        let r = results
        return n >= 1 && n <= min(9, r.count) ? r[n - 1] : nil
    }
}
