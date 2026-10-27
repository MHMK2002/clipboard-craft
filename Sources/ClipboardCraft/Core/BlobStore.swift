import Foundation
import UniformTypeIdentifiers

/// On-disk storage for clip payloads: raw pasteboard representations, archived file copies,
/// primary images and thumbnails. Layout: `Blobs/<clip-id>/…`. Safe to use from any thread.
struct BlobStore: Sendable {
    let root: URL

    static let shared: BlobStore = {
        let store = BlobStore(root: AppPaths.dataFolder.appendingPathComponent("Blobs", isDirectory: true))
        try? FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        return store
    }()

    func folder(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func url(for id: UUID, relative: String) -> URL {
        folder(for: id).appendingPathComponent(relative)
    }

    func thumbnailURL(for id: UUID) -> URL { url(for: id, relative: "thumb.png") }

    private func manifestURL(for id: UUID) -> URL { url(for: id, relative: "reps.json") }

    @discardableResult
    func ensureFolder(for id: UUID) throws -> URL {
        let f = folder(for: id)
        try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        return f
    }

    /// Writes all pasteboard representations and their manifest.
    @discardableResult
    func writeReps(_ items: [[(type: String, data: Data)]], for id: UUID) throws -> RepManifest {
        guard !items.isEmpty else { return RepManifest(items: []) }
        let folder = try ensureFolder(for: id)
        var manifest = RepManifest(items: [])
        for (i, reps) in items.enumerated() {
            var entries: [RepEntry] = []
            for (j, rep) in reps.enumerated() {
                let ext = UTType(rep.type)?.preferredFilenameExtension ?? "bin"
                let name = "rep-\(i)-\(j).\(ext)"
                try rep.data.write(to: folder.appendingPathComponent(name), options: .atomic)
                entries.append(RepEntry(type: rep.type, file: name, size: rep.data.count))
            }
            manifest.items.append(entries)
        }
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL(for: id), options: .atomic)
        return manifest
    }

    func manifest(for id: UUID) -> RepManifest? {
        guard let data = try? Data(contentsOf: manifestURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(RepManifest.self, from: data)
    }

    func loadReps(for id: UUID) -> [[(type: String, data: Data)]] {
        guard let manifest = manifest(for: id) else { return [] }
        return manifest.items.map { entries in
            entries.compactMap { e in
                guard let d = try? Data(contentsOf: url(for: id, relative: e.file), options: .mappedIfSafe) else { return nil }
                return (e.type, d)
            }
        }
    }

    func repData(for id: UUID, type: String) -> Data? {
        guard let manifest = manifest(for: id) else { return nil }
        for entries in manifest.items {
            if let e = entries.first(where: { $0.type == type }) {
                return try? Data(contentsOf: url(for: id, relative: e.file), options: .mappedIfSafe)
            }
        }
        return nil
    }

    /// Replaces the stored representations of a clip with a single plain-text one.
    func replaceWithPlainText(_ text: String, for id: UUID) {
        if let manifest = manifest(for: id) {
            for e in manifest.items.flatMap({ $0 }) {
                try? FileManager.default.removeItem(at: url(for: id, relative: e.file))
            }
        }
        _ = try? writeReps([[(PBType.plainText, Data(text.utf8))]], for: id)
    }

    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }

    func size(of id: UUID) -> Int64 {
        Self.directorySize(folder(for: id))
    }

    func allClipFolderIDs() -> [UUID] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.compactMap(UUID.init(uuidString:))
    }

    /// Allocated size of a file or folder. Enumeration stops after `maxFiles` entries so huge
    /// folders (e.g. a whole home directory on the clipboard) can't stall capture.
    static func directorySize(_ url: URL, maxFiles: Int = 200_000) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: keys)
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        var seen = 0
        for case let file as URL in e {
            seen += 1
            if seen > maxFiles { break }
            guard let v = try? file.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}

enum AppPaths {
    static let dataFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = base.appendingPathComponent("Clipboard Craft", isDirectory: true)
        #if DEBUG
        if let custom = ProcessInfo.processInfo.environment["CC_DATA_DIR"] { url = URL(fileURLWithPath: custom, isDirectory: true) }
        #endif
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var databaseURL: URL { dataFolder.appendingPathComponent("library.sqlite") }
}
