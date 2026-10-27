import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct DatabaseError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// Thin SQLite wrapper. All access happens on the main actor; queries are small and fast.
@MainActor
final class Database {
    private var db: OpaquePointer?

    init(url: URL) throws {
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            throw DatabaseError(message: "Cannot open database at \(url.path)")
        }
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try migrate()
    }

    deinit { sqlite3_close(db) }

    // MARK: Schema

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS clips (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            copy_count INTEGER NOT NULL DEFAULT 1,
            title TEXT NOT NULL DEFAULT '',
            text TEXT,
            hash TEXT NOT NULL,
            source_bundle_id TEXT,
            source_app_name TEXT,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            byte_size INTEGER NOT NULL DEFAULT 0,
            meta TEXT,
            deleted_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_clips_hash ON clips(hash);
        CREATE INDEX IF NOT EXISTS idx_clips_updated ON clips(updated_at);
        CREATE TABLE IF NOT EXISTS collections (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            symbol TEXT NOT NULL,
            color TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS clip_collections (
            clip_id TEXT NOT NULL,
            collection_id TEXT NOT NULL,
            PRIMARY KEY (clip_id, collection_id)
        );
        """)
    }

    // MARK: Primitives

    func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DatabaseError(message: msg)
        }
    }

    enum Value {
        case text(String?)
        case int(Int64)
        case double(Double?)
    }

    @discardableResult
    private func run(_ sql: String, _ values: [Value] = [], row: ((OpaquePointer) -> Void)? = nil) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            NSLog("ClipboardCraft SQL prepare error: \(String(cString: sqlite3_errmsg(db))) — \(sql)")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        for (i, v) in values.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case .text(let s):
                if let s { sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, idx) }
            case .int(let n):
                sqlite3_bind_int64(stmt, idx, n)
            case .double(let d):
                if let d { sqlite3_bind_double(stmt, idx, d) } else { sqlite3_bind_null(stmt, idx) }
            }
        }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { row?(stmt); continue }
            if rc == SQLITE_DONE { return true }
            NSLog("ClipboardCraft SQL step error: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
    }

    private func transaction(_ body: () -> Void) {
        try? execute("BEGIN IMMEDIATE;")
        body()
        try? execute("COMMIT;")
    }

    private static func string(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: c)
    }

    // MARK: Clips

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    func loadClips() -> [ClipItem] {
        var memberships: [UUID: Set<UUID>] = [:]
        run("SELECT clip_id, collection_id FROM clip_collections") { stmt in
            if let c = Self.string(stmt, 0).flatMap(UUID.init), let col = Self.string(stmt, 1).flatMap(UUID.init) {
                memberships[c, default: []].insert(col)
            }
        }
        var items: [ClipItem] = []
        let sql = """
        SELECT id, kind, created_at, updated_at, copy_count, title, text, hash, source_bundle_id, source_app_name,
               is_pinned, is_favorite, byte_size, meta
        FROM clips WHERE deleted_at IS NULL ORDER BY updated_at DESC
        """
        run(sql) { stmt in
            guard let id = Self.string(stmt, 0).flatMap(UUID.init),
                  let kind = Self.string(stmt, 1).flatMap(ClipKind.init(rawValue:)) else { return }
            var meta = ClipMeta()
            if let json = Self.string(stmt, 13), let data = json.data(using: .utf8) {
                meta = (try? Self.decoder.decode(ClipMeta.self, from: data)) ?? ClipMeta()
            }
            var item = ClipItem(
                id: id,
                kind: kind,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                copyCount: Int(sqlite3_column_int64(stmt, 4)),
                title: Self.string(stmt, 5) ?? "",
                text: Self.string(stmt, 6),
                contentHash: Self.string(stmt, 7) ?? "",
                sourceBundleID: Self.string(stmt, 8),
                sourceAppName: Self.string(stmt, 9),
                isPinned: sqlite3_column_int(stmt, 10) != 0,
                isFavorite: sqlite3_column_int(stmt, 11) != 0,
                byteSize: sqlite3_column_int64(stmt, 12),
                meta: meta,
                collectionIDs: memberships[id] ?? []
            )
            item.searchKey = SearchFold.searchKey(for: item)
            items.append(item)
        }
        return items
    }

    func save(_ item: ClipItem) {
        let metaJSON = (try? Self.encoder.encode(item.meta)).flatMap { String(data: $0, encoding: .utf8) }
        run("""
        INSERT INTO clips (id, kind, created_at, updated_at, copy_count, title, text, hash, source_bundle_id,
                           source_app_name, is_pinned, is_favorite, byte_size, meta, deleted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
        ON CONFLICT(id) DO UPDATE SET
            kind = excluded.kind, created_at = excluded.created_at, updated_at = excluded.updated_at,
            copy_count = excluded.copy_count, title = excluded.title, text = excluded.text, hash = excluded.hash,
            source_bundle_id = excluded.source_bundle_id, source_app_name = excluded.source_app_name,
            is_pinned = excluded.is_pinned, is_favorite = excluded.is_favorite, byte_size = excluded.byte_size,
            meta = excluded.meta, deleted_at = NULL
        """, [
            .text(item.id.uuidString), .text(item.kind.rawValue),
            .double(item.createdAt.timeIntervalSince1970), .double(item.updatedAt.timeIntervalSince1970),
            .int(Int64(item.copyCount)), .text(item.title), .text(item.text), .text(item.contentHash),
            .text(item.sourceBundleID), .text(item.sourceAppName),
            .int(item.isPinned ? 1 : 0), .int(item.isFavorite ? 1 : 0), .int(item.byteSize), .text(metaJSON)
        ])
    }

    func setMembership(clip: UUID, collections: Set<UUID>) {
        transaction {
            run("DELETE FROM clip_collections WHERE clip_id = ?", [.text(clip.uuidString)])
            for c in collections {
                run("INSERT OR IGNORE INTO clip_collections (clip_id, collection_id) VALUES (?, ?)",
                    [.text(clip.uuidString), .text(c.uuidString)])
            }
        }
    }

    func markDeleted(_ ids: [UUID], at date: Date?) {
        transaction {
            for id in ids {
                run("UPDATE clips SET deleted_at = ? WHERE id = ?", [.double(date?.timeIntervalSince1970), .text(id.uuidString)])
            }
        }
    }

    /// IDs of soft-deleted clips (optionally only those deleted before `before`).
    func deletedIDs(before: Date? = nil) -> [UUID] {
        var ids: [UUID] = []
        if let before {
            run("SELECT id FROM clips WHERE deleted_at IS NOT NULL AND deleted_at < ?", [.double(before.timeIntervalSince1970)]) { stmt in
                if let id = Self.string(stmt, 0).flatMap(UUID.init) { ids.append(id) }
            }
        } else {
            run("SELECT id FROM clips WHERE deleted_at IS NOT NULL") { stmt in
                if let id = Self.string(stmt, 0).flatMap(UUID.init) { ids.append(id) }
            }
        }
        return ids
    }

    func hardDelete(_ ids: [UUID]) {
        transaction {
            for id in ids {
                run("DELETE FROM clips WHERE id = ?", [.text(id.uuidString)])
                run("DELETE FROM clip_collections WHERE clip_id = ?", [.text(id.uuidString)])
            }
        }
    }

    func allClipIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        run("SELECT id FROM clips") { stmt in
            if let id = Self.string(stmt, 0).flatMap(UUID.init) { ids.insert(id) }
        }
        return ids
    }

    // MARK: Collections

    func loadCollections() -> [ClipCollection] {
        var result: [ClipCollection] = []
        run("SELECT id, name, symbol, color, sort_order FROM collections ORDER BY sort_order, name") { stmt in
            guard let id = Self.string(stmt, 0).flatMap(UUID.init) else { return }
            result.append(ClipCollection(
                id: id,
                name: Self.string(stmt, 1) ?? "",
                symbol: Self.string(stmt, 2) ?? "folder.fill",
                color: CollectionColor(rawValue: Self.string(stmt, 3) ?? "") ?? .blue,
                sortOrder: Int(sqlite3_column_int64(stmt, 4))
            ))
        }
        return result
    }

    func save(_ c: ClipCollection) {
        run("""
        INSERT INTO collections (id, name, symbol, color, sort_order) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET name = excluded.name, symbol = excluded.symbol, color = excluded.color,
            sort_order = excluded.sort_order
        """, [.text(c.id.uuidString), .text(c.name), .text(c.symbol), .text(c.color.rawValue), .int(Int64(c.sortOrder))])
    }

    func deleteCollection(_ id: UUID) {
        transaction {
            run("DELETE FROM collections WHERE id = ?", [.text(id.uuidString)])
            run("DELETE FROM clip_collections WHERE collection_id = ?", [.text(id.uuidString)])
        }
    }

    func checkpoint() {
        try? execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }
}
