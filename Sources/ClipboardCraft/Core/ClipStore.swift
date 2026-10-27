import AppKit
import Observation

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var symbol: String
    var undoIDs: [UUID]?
}

struct ClipFilter: Equatable {
    var kinds: Set<ClipKind>?
    var pinnedOnly = false
    var favoritesOnly = false
    var appBundleID: String?
    var collectionID: UUID?

    static let all = ClipFilter()
}

/// Parsed search string. Supports free terms plus `type:` `is:` `app:` and `in:` tokens.
struct SearchQuery {
    var terms: [String] = []
    var kinds: Set<ClipKind> = []
    var pinned = false
    var favorite = false
    var app: String?
    var collection: String?

    init(_ raw: String) {
        for token in raw.split(whereSeparator: \.isWhitespace).map(String.init) {
            let lower = token.lowercased()
            if let v = lower.value(after: "type:") ?? lower.value(after: "kind:") {
                kinds.formUnion(ClipKind.allCases.filter { $0.searchAliases.contains(v) })
            } else if let v = lower.value(after: "is:") {
                if v.hasPrefix("pin") { pinned = true } else if v.hasPrefix("fav") || v.hasPrefix("star") { favorite = true }
            } else if let v = lower.value(after: "app:") {
                app = SearchFold.fold(v)
            } else if let v = lower.value(after: "in:") {
                collection = SearchFold.fold(v)
            } else {
                terms.append(SearchFold.fold(token))
            }
        }
    }

    var isEmpty: Bool { terms.isEmpty && kinds.isEmpty && !pinned && !favorite && app == nil && collection == nil }
}

private extension String {
    func value(after prefix: String) -> String? {
        guard hasPrefix(prefix), count > prefix.count else { return nil }
        return String(dropFirst(prefix.count))
    }
}

@MainActor
@Observable
final class ClipStore {
    private(set) var items: [ClipItem] = []
    private(set) var collections: [ClipCollection] = []
    private(set) var revision = 0
    var toast: Toast?

    @ObservationIgnored let db: Database
    @ObservationIgnored let blobs = BlobStore.shared
    @ObservationIgnored private var positions: [UUID: Int] = [:]
    @ObservationIgnored private var trash: [UUID: ClipItem] = [:]
    @ObservationIgnored private var deletionBatches: [[UUID]] = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored var onInsert: ((ClipItem) -> Void)?

    init(db: Database) {
        self.db = db
    }

    // MARK: Loading

    func load() {
        // Anything soft-deleted in a previous session is gone for good.
        let stale = db.deletedIDs()
        if !stale.isEmpty { db.hardDelete(stale); removeBlobs(stale) }

        items = db.loadClips()
        collections = db.loadCollections()
        if collections.isEmpty, items.isEmpty || !UserDefaults.standard.bool(forKey: "seededCollections") {
            seedCollections()
        }
        reindex()
        cleanOrphanBlobs()
        runMaintenance()
    }

    private func seedCollections() {
        let seeds: [(String, String, CollectionColor)] = [
            ("Work", "briefcase.fill", .blue),
            ("Personal", "person.fill", .green),
            ("Code", "chevron.left.forwardslash.chevron.right", .purple),
            ("Research", "magnifyingglass", .orange)
        ]
        for (i, s) in seeds.enumerated() {
            let c = ClipCollection(id: UUID(), name: s.0, symbol: s.1, color: s.2, sortOrder: i)
            db.save(c)
            collections.append(c)
        }
        UserDefaults.standard.set(true, forKey: "seededCollections")
    }

    private func cleanOrphanBlobs() {
        let known = db.allClipIDs()
        let blobs = self.blobs
        DispatchQueue.global(qos: .utility).async {
            for id in blobs.allClipFolderIDs() where !known.contains(id) { blobs.remove(id) }
        }
    }

    private func reindex() {
        positions = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })
        revision &+= 1
    }

    // MARK: Lookup

    func item(_ id: UUID) -> ClipItem? {
        guard let i = positions[id], i < items.count, items[i].id == id else { return nil }
        return items[i]
    }

    func items(_ ids: some Sequence<UUID>) -> [ClipItem] {
        ids.compactMap(item).sorted { $0.updatedAt > $1.updatedAt }
    }

    func collection(_ id: UUID) -> ClipCollection? { collections.first { $0.id == id } }

    // MARK: Capture

    func insert(_ item: ClipItem) {
        items.insert(item, at: 0)
        db.save(item)
        reindex()
        onInsert?(item)
        enforceLimitsSoon()
    }

    /// Returns true when the capture was absorbed by an existing clip.
    func handleDuplicate(hash: String, behavior: DuplicateBehavior, sourceBundleID: String?, sourceAppName: String?) -> Bool {
        guard let existing = items.first(where: { $0.contentHash == hash }) else { return false }
        switch behavior {
        case .keepBoth:
            return false
        case .ignore:
            return true
        case .moveToTop:
            mutate(existing.id) {
                $0.updatedAt = .now
                $0.copyCount += 1
                if let sourceBundleID { $0.sourceBundleID = sourceBundleID; $0.sourceAppName = sourceAppName }
            }
            moveToTop(existing.id)
            return true
        }
    }

    func bump(_ id: UUID) {
        mutate(id) { $0.updatedAt = .now; $0.copyCount += 1 }
        moveToTop(id)
    }

    private func moveToTop(_ id: UUID) {
        guard let i = positions[id], i > 0 else { return }
        let item = items.remove(at: i)
        items.insert(item, at: 0)
        reindex()
    }

    // MARK: Mutations

    private func mutate(_ id: UUID, _ change: (inout ClipItem) -> Void) {
        guard let i = positions[id] else { return }
        change(&items[i])
        db.save(items[i])
        revision &+= 1
    }

    func setPinned(_ ids: [UUID], _ pinned: Bool) {
        for id in ids { mutate(id) { $0.isPinned = pinned } }
    }

    func togglePin(_ ids: [UUID]) {
        let target = !ids.compactMap(item).allSatisfy(\.isPinned)
        setPinned(ids, target)
    }

    func setFavorite(_ ids: [UUID], _ fav: Bool) {
        for id in ids { mutate(id) { $0.isFavorite = fav } }
    }

    func toggleFavorite(_ ids: [UUID]) {
        let target = !ids.compactMap(item).allSatisfy(\.isFavorite)
        setFavorite(ids, target)
    }

    func setCollection(_ collectionID: UUID, member: Bool, for ids: [UUID]) {
        for id in ids {
            mutate(id) {
                if member { $0.collectionIDs.insert(collectionID) } else { $0.collectionIDs.remove(collectionID) }
            }
            if let item = item(id) { db.setMembership(clip: id, collections: item.collectionIDs) }
        }
    }

    func toggleCollection(_ collectionID: UUID, for ids: [UUID]) {
        let allMember = ids.compactMap(item).allSatisfy { $0.collectionIDs.contains(collectionID) }
        setCollection(collectionID, member: !allMember, for: ids)
    }

    func updateText(_ id: UUID, to newText: String) {
        guard let old = item(id), old.kind.isTextual || old.kind == .other else { return }
        blobs.replaceWithPlainText(newText, for: id)
        mutate(id) {
            $0.text = newText
            $0.title = ContentClassifier.makeTitle(newText)
            $0.contentHash = "text:" + ContentClassifier.sha(newText)
            $0.meta.charCount = newText.count
            $0.meta.lineCount = newText.trimmingCharacters(in: .whitespacesAndNewlines).reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
            $0.meta.wordCount = newText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            $0.meta.edited = true
            $0.meta.richType = nil
            if $0.kind == .richText || $0.kind == .other { $0.kind = .text }
            if $0.kind == .color { $0.meta.colorHex = ColorParser.parse(newText)?.hex }
            if $0.kind == .code { $0.meta.codeLanguage = CodeDetector.detect(newText) ?? $0.meta.codeLanguage }
            $0.byteSize = blobs.size(of: id)
            $0.searchKey = SearchFold.searchKey(for: $0)
        }
        showToast("Changes saved", symbol: "checkmark.circle.fill")
    }

    func setKind(_ ids: [UUID], to kind: ClipKind) {
        for id in ids {
            mutate(id) {
                guard $0.kind.isTextual, let text = $0.text else { return }
                $0.kind = kind
                if kind == .code, $0.meta.codeLanguage == nil { $0.meta.codeLanguage = CodeDetector.detect(text) ?? "Code" }
            }
        }
    }

    func setCodeLanguage(_ id: UUID, _ language: String) {
        mutate(id) { $0.meta.codeLanguage = language; $0.searchKey = SearchFold.searchKey(for: $0) }
    }

    func setLinkTitle(_ id: UUID, _ title: String) {
        mutate(id) { $0.meta.linkTitle = title; $0.searchKey = SearchFold.searchKey(for: $0) }
    }

    // MARK: Deletion & undo

    /// Soft-deletes clips so the action can be undone.
    func delete(_ ids: [UUID]) {
        let removed = ids.compactMap(item)
        guard !removed.isEmpty else { return }
        let set = Set(removed.map(\.id))
        for r in removed { trash[r.id] = r }
        items.removeAll { set.contains($0.id) }
        db.markDeleted(removed.map(\.id), at: .now)
        deletionBatches.append(removed.map(\.id))
        if deletionBatches.count > 30 { deletionBatches.removeFirst() }
        reindex()
        let msg = removed.count == 1 ? "Deleted “\(removed[0].displayTitle.prefix(40))”" : "Deleted \(removed.count) items"
        showToast(msg, symbol: "trash.fill", undo: removed.map(\.id))
    }

    func restore(_ ids: [UUID]) {
        let restored = ids.compactMap { trash.removeValue(forKey: $0) }
        guard !restored.isEmpty else { return }
        db.markDeleted(restored.map(\.id), at: nil)
        items.append(contentsOf: restored)
        items.sort { $0.updatedAt > $1.updatedAt }
        deletionBatches.removeAll { Set($0) == Set(ids) }
        reindex()
        showToast(restored.count == 1 ? "Item restored" : "\(restored.count) items restored", symbol: "arrow.uturn.backward.circle.fill")
    }

    var canUndoDeletion: Bool { deletionBatches.last.map { $0.contains { trash[$0] != nil } } ?? false }

    func undoLastDeletion() {
        guard let batch = deletionBatches.popLast() else { return }
        restore(batch)
    }

    /// Permanently removes soft-deleted clips older than `age` seconds.
    func purgeTrash(olderThan age: TimeInterval = 0) {
        let ids = db.deletedIDs(before: Date().addingTimeInterval(-age))
        guard !ids.isEmpty else { return }
        for id in ids { trash[id] = nil }
        db.hardDelete(ids)
        removeBlobs(ids)
    }

    private func hardDelete(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        items.removeAll { set.contains($0.id) }
        db.hardDelete(ids)
        removeBlobs(ids)
        reindex()
    }

    private func removeBlobs(_ ids: [UUID]) {
        let blobs = self.blobs
        DispatchQueue.global(qos: .utility).async { ids.forEach(blobs.remove) }
    }

    func clearHistory(keepProtected: Bool) {
        let victims = items.filter { !keepProtected || !$0.isProtected }.map(\.id)
        hardDelete(victims)
        purgeTrash()
        db.checkpoint()
        showToast("History cleared", symbol: "sparkles")
    }

    func clear(kind: ClipKind) {
        hardDelete(items.filter { $0.kind == kind && !$0.isProtected }.map(\.id))
    }

    // MARK: Maintenance

    @ObservationIgnored private var limitsScheduled = false

    private func enforceLimitsSoon() {
        guard !limitsScheduled else { return }
        limitsScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                self?.limitsScheduled = false
                self?.runMaintenance()
            }
        }
    }

    /// Applies retention period, item count and storage limits. Protected items are never removed.
    func runMaintenance() {
        let s = AppSettings.shared
        var victims = Set<UUID>()
        if let interval = s.retention.interval {
            let cutoff = Date().addingTimeInterval(-interval)
            for i in items where !i.isProtected && i.updatedAt < cutoff { victims.insert(i.id) }
        }
        var remaining = items.filter { !victims.contains($0.id) }
        if s.maxItems > 0, remaining.count > s.maxItems {
            var excess = remaining.count - s.maxItems
            for i in remaining.reversed() where excess > 0 && !i.isProtected {
                victims.insert(i.id); excess -= 1
            }
            remaining.removeAll { victims.contains($0.id) }
        }
        if let maxBytes = s.maxStorageBytes {
            var total = remaining.reduce(Int64(0)) { $0 + $1.byteSize }
            for i in remaining.reversed() where total > maxBytes && !i.isProtected {
                victims.insert(i.id); total -= i.byteSize
            }
        }
        hardDelete(Array(victims))
        purgeTrash(olderThan: 15 * 60)
    }

    // MARK: Collections

    @discardableResult
    func createCollection(name: String, symbol: String, color: CollectionColor) -> ClipCollection {
        let c = ClipCollection(id: UUID(), name: name, symbol: symbol, color: color,
                               sortOrder: (collections.map(\.sortOrder).max() ?? 0) + 1)
        db.save(c)
        collections.append(c)
        return c
    }

    func updateCollection(_ c: ClipCollection) {
        guard let i = collections.firstIndex(where: { $0.id == c.id }) else { return }
        collections[i] = c
        db.save(c)
    }

    func deleteCollection(_ id: UUID) {
        db.deleteCollection(id)
        collections.removeAll { $0.id == id }
        for i in items.indices where items[i].collectionIDs.contains(id) { items[i].collectionIDs.remove(id) }
        revision &+= 1
    }

    func moveCollections(from source: IndexSet, to destination: Int) {
        collections.move(fromOffsets: source, toOffset: destination)
        for i in collections.indices {
            collections[i].sortOrder = i
            db.save(collections[i])
        }
    }

    // MARK: Querying

    func results(query: String, filter: ClipFilter, pinnedFirst: Bool = false) -> [ClipItem] {
        let q = SearchQuery(query)
        let collectionMatches: Set<UUID>? = q.collection.map { name in
            Set(collections.filter { SearchFold.fold($0.name).hasPrefix(name) }.map(\.id))
        }
        let result = items.filter { item in
            if let kinds = filter.kinds, !kinds.contains(item.kind) { return false }
            if filter.pinnedOnly, !item.isPinned { return false }
            if filter.favoritesOnly, !item.isFavorite { return false }
            if let app = filter.appBundleID, item.sourceBundleID != app { return false }
            if let c = filter.collectionID, !item.collectionIDs.contains(c) { return false }
            if !q.kinds.isEmpty, !q.kinds.contains(item.kind) { return false }
            if q.pinned, !item.isPinned { return false }
            if q.favorite, !item.isFavorite { return false }
            if let app = q.app, !SearchFold.fold(item.sourceAppName ?? "").contains(app) { return false }
            if let cm = collectionMatches, item.collectionIDs.isDisjoint(with: cm) { return false }
            for term in q.terms where !item.searchKey.contains(term) { return false }
            return true
        }
        guard pinnedFirst else { return result }
        return result.filter(\.isPinned) + result.filter { !$0.isPinned }
    }

    func count(of kind: ClipKind) -> Int { items.reduce(0) { $0 + ($1.kind == kind ? 1 : 0) } }

    var pinnedCount: Int { items.reduce(0) { $0 + ($1.isPinned ? 1 : 0) } }
    var favoriteCount: Int { items.reduce(0) { $0 + ($1.isFavorite ? 1 : 0) } }

    func count(inCollection id: UUID) -> Int { items.reduce(0) { $0 + ($1.collectionIDs.contains(id) ? 1 : 0) } }

    struct AppSource: Identifiable, Hashable {
        var id: String { bundleID }
        let bundleID: String
        let name: String
        let count: Int
    }

    var appSources: [AppSource] {
        var counts: [String: (String, Int)] = [:]
        for i in items {
            guard let b = i.sourceBundleID else { continue }
            let prev = counts[b] ?? (i.sourceAppName ?? b, 0)
            counts[b] = (prev.0, prev.1 + 1)
        }
        return counts.map { AppSource(bundleID: $0.key, name: $0.value.0, count: $0.value.1) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.byteSize } }

    func bytes(of kind: ClipKind) -> Int64 { items.reduce(0) { $0 + ($1.kind == kind ? $1.byteSize : 0) } }

    // MARK: Toasts

    func showToast(_ message: String, symbol: String, undo: [UUID]? = nil) {
        let t = Toast(message: message, symbol: symbol, undoIDs: undo)
        toast = t
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undo == nil ? 2.2 : 5))
            guard !Task.isCancelled else { return }
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }
}

#if DEBUG
extension ClipStore {
    /// Showcase/demo helper: moves a clip in time and keeps the list ordered.
    func debugSetDate(_ id: UUID, _ date: Date) {
        mutate(id) { $0.updatedAt = date; $0.createdAt = date }
        items.sort { $0.updatedAt > $1.updatedAt }
        reindex()
    }
}
#endif
