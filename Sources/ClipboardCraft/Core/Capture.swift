import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Snapshot

/// An immutable copy of the pasteboard contents, taken on the main thread and processed in the background.
struct PasteboardSnapshot: @unchecked Sendable {
    var items: [[(type: String, data: Data)]]
    var fileURLs: [URL]
    var sourceBundleID: String?
    var sourceAppName: String?
    var date = Date()

    static let maxRepBytes = 150 * 1_048_576

    var allTypes: [String] {
        var seen = Set<String>()
        return items.flatMap { $0.map(\.type) }.filter { seen.insert($0).inserted }
    }

    func data(for type: String) -> Data? {
        for item in items { if let r = item.first(where: { $0.type == type }) { return r.data } }
        return nil
    }

    func has(_ type: String) -> Bool { items.contains { $0.contains { $0.type == type } } }

    @MainActor
    static func capture(from pb: NSPasteboard, respectPrivacy: Bool) -> PasteboardSnapshot? {
        guard let pbItems = pb.pasteboardItems, !pbItems.isEmpty else { return nil }
        let allTypes = Set(pbItems.flatMap { $0.types.map(\.rawValue) })
        if allTypes.contains(PBType.own) { return nil }
        if respectPrivacy, !allTypes.isDisjoint(with: PBType.privacyMarkers) { return nil }

        // Files: only read the URLs – icon previews and other flavours are not needed.
        let fileURLs: [URL] = pbItems.compactMap { item in
            guard let s = item.string(forType: .fileURL), let url = URL(string: s), url.isFileURL else { return nil }
            return ((url as NSURL).filePathURL ?? url).standardizedFileURL
        }
        if !fileURLs.isEmpty {
            return PasteboardSnapshot(items: [], fileURLs: fileURLs)
        }

        var items: [[(type: String, data: Data)]] = []
        for item in pbItems {
            var reps: [(type: String, data: Data)] = []
            for type in item.types {
                let raw = type.rawValue
                if PBType.skipped.contains(raw) { continue }
                guard let data = item.data(forType: type), data.count <= maxRepBytes else { continue }
                reps.append((raw, data))
            }
            if !reps.isEmpty { items.append(reps) }
        }
        guard !items.isEmpty else { return nil }
        return PasteboardSnapshot(items: items, fileURLs: [])
    }
}

// MARK: - Classification

struct Classification {
    var kind: ClipKind
    var title: String
    var text: String?
    var meta: ClipMeta
    var hash: String
}

enum ContentClassifier {
    static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha(_ string: String) -> String { sha(Data(string.utf8)) }

    static func plainText(of s: PasteboardSnapshot) -> String? {
        if let d = s.data(for: PBType.plainText), let t = String(data: d, encoding: .utf8) { return t }
        if let d = s.data(for: PBType.utf16Text), let t = String(data: d, encoding: .utf16) { return t }
        if let d = s.data(for: PBType.legacyString), let t = String(data: d, encoding: .utf8) { return t }
        if let d = s.data(for: PBType.rtf), let a = NSAttributedString(rtf: d, documentAttributes: nil) { return a.string }
        if let d = s.data(for: PBType.url), let t = String(data: d, encoding: .utf8) { return t }
        return nil
    }

    static func classify(_ s: PasteboardSnapshot) -> Classification? {
        if !s.fileURLs.isEmpty { return classifyFiles(s.fileURLs) }

        let text = plainText(of: s)
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let imageType = PBType.imageTypes.first(where: s.has)

        // Images: an image flavour without meaningful accompanying text (or with just a URL, e.g. browsers).
        if let imageType, let data = s.data(for: imageType), trimmed.isEmpty || isSingleURL(trimmed) {
            var meta = ClipMeta()
            if let src = CGImageSourceCreateWithData(data as CFData, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                meta.imageWidth = props[kCGImagePropertyPixelWidth] as? Int
                meta.imageHeight = props[kCGImagePropertyPixelHeight] as? Int
            }
            meta.imageType = imageType
            meta.types = s.allTypes
            return Classification(kind: .image, title: "Image", text: nil, meta: meta, hash: "img:" + sha(data))
        }

        if !trimmed.isEmpty, let text {
            var meta = ClipMeta()
            meta.types = s.allTypes
            meta.charCount = text.count
            meta.lineCount = trimmed.reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
            meta.wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let title = makeTitle(text)

            if isSingleURL(trimmed), let url = normalizedURL(trimmed) {
                meta.url = url.absoluteString
                meta.urlHost = url.host(percentEncoded: false) ?? url.scheme
                return Classification(kind: .link, title: trimmed, text: trimmed, meta: meta, hash: "link:" + sha(trimmed))
            }
            if let color = ColorParser.parse(trimmed) {
                meta.colorHex = color.hex
                return Classification(kind: .color, title: trimmed, text: trimmed, meta: meta, hash: "color:" + sha(trimmed.lowercased()))
            }
            if let lang = CodeDetector.detect(text) {
                meta.codeLanguage = lang
                return Classification(kind: .code, title: title, text: text, meta: meta, hash: "text:" + sha(text))
            }
            let isRich = s.has(PBType.rtf) || s.has(PBType.rtfd) || s.has(PBType.html)
            if isRich {
                meta.richType = s.has(PBType.rtf) ? "rtf" : (s.has(PBType.rtfd) ? "rtfd" : "html")
                return Classification(kind: .richText, title: title, text: text, meta: meta, hash: "rich:" + sha(text))
            }
            return Classification(kind: .text, title: title, text: text, meta: meta, hash: "text:" + sha(text))
        }

        // Anything else: keep the raw flavours.
        guard let first = s.items.first?.first else { return nil }
        var meta = ClipMeta()
        meta.types = s.allTypes
        let desc = UTType(first.type)?.localizedDescription ?? first.type
        var hasher = SHA256()
        for item in s.items { for rep in item { hasher.update(data: Data(rep.type.utf8)); hasher.update(data: rep.data.prefix(1_000_000)) } }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return Classification(kind: .other, title: desc.capitalized, text: nil, meta: meta, hash: "raw:" + hash)
    }

    static func classifyFiles(_ urls: [URL]) -> Classification {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .contentTypeKey, .contentModificationDateKey, .localizedNameKey]
        var entries: [FileEntry] = []
        var hashParts: [String] = []
        for url in urls {
            let v = try? url.resourceValues(forKeys: keys)
            let isDir = v?.isDirectory ?? false
            let size = isDir ? BlobStore.directorySize(url) : Int64(v?.fileSize ?? 0)
            entries.append(FileEntry(
                name: url.lastPathComponent,
                originalPath: url.path,
                storedPath: nil,
                size: size,
                typeIdentifier: v?.contentType?.identifier ?? (isDir ? UTType.folder.identifier : nil),
                isDirectory: isDir,
                modifiedAt: v?.contentModificationDate
            ))
            hashParts.append("\(url.path)|\(size)|\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        var meta = ClipMeta()
        meta.files = entries
        meta.types = [PBType.fileURL]
        let title = entries.count == 1 ? entries[0].name : "\(entries.count) files"
        return Classification(kind: .file, title: title, text: entries.map(\.originalPath).joined(separator: "\n"),
                              meta: meta, hash: "files:" + sha(hashParts.joined(separator: "\n")))
    }

    static func makeTitle(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let collapsed = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        return String(collapsed.prefix(240))
    }

    static func isSingleURL(_ s: String) -> Bool {
        guard !s.contains(where: { $0.isWhitespace }), s.count < 4096 else { return false }
        return normalizedURL(s) != nil
    }

    static func normalizedURL(_ s: String) -> URL? {
        let lower = s.lowercased()
        let schemes = ["http://", "https://", "ftp://", "mailto:", "ssh://", "sftp://", "file://", "smb://", "afp://", "vnc://", "tel:", "facetime:", "x-apple."]
        if schemes.contains(where: lower.hasPrefix) { return URL(string: s) }
        if lower.hasPrefix("www."), s.contains("."), let url = URL(string: "https://" + s) { return url }
        return nil
    }
}

// MARK: - Processing pipeline

/// Turns snapshots into stored clips on a serial background queue, so ordering is preserved
/// and heavy work (hashing, file archiving, thumbnails) never blocks the UI.
final class CaptureProcessor: @unchecked Sendable {
    static let shared = CaptureProcessor()
    private let queue = DispatchQueue(label: "app.clipboardcraft.capture", qos: .userInitiated)
    private let blobs = BlobStore.shared

    struct Options: Sendable {
        var duplicateBehavior: DuplicateBehavior
        var saveFileCopies: Bool
        var maxFileCopyBytes: Int64
    }

    func process(_ snapshot: PasteboardSnapshot, options: Options, store: ClipStore) {
        queue.async { [blobs] in
            guard let c = ContentClassifier.classify(snapshot) else { return }

            // Duplicate handling is decided on the main actor, which owns the store.
            if options.duplicateBehavior != .keepBoth {
                let handled = DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        store.handleDuplicate(hash: c.hash, behavior: options.duplicateBehavior,
                                              sourceBundleID: snapshot.sourceBundleID, sourceAppName: snapshot.sourceAppName)
                    }
                }
                if handled { return }
            }

            let id = UUID()
            var meta = c.meta
            do {
                try blobs.ensureFolder(for: id)
                switch c.kind {
                case .file:
                    if options.saveFileCopies { meta.files = Self.archiveFiles(meta.files ?? [], id: id, blobs: blobs, limit: options.maxFileCopyBytes) }
                case .image:
                    let (reps, primary) = Self.optimizedImageReps(snapshot.items)
                    let manifest = try blobs.writeReps(reps, for: id)
                    if let primary {
                        meta.imageFile = manifest.items.flatMap { $0 }.first { $0.type == primary.type }?.file
                        meta.imageType = primary.type
                        Self.writeThumbnail(from: primary.data, to: blobs.thumbnailURL(for: id))
                    }
                default:
                    try blobs.writeReps(snapshot.items, for: id)
                }
            } catch {
                NSLog("ClipboardCraft: failed to store clip: \(error)")
            }
            let size = blobs.size(of: id)

            var item = ClipItem(
                id: id, kind: c.kind, createdAt: snapshot.date, updatedAt: snapshot.date, copyCount: 1,
                title: c.title, text: c.text, contentHash: c.hash,
                sourceBundleID: snapshot.sourceBundleID, sourceAppName: snapshot.sourceAppName,
                isPinned: false, isFavorite: false, byteSize: size, meta: meta, collectionIDs: []
            )
            item.searchKey = SearchFold.searchKey(for: item)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { store.insert(item) }
            }
        }
    }

    /// Copies files into the clip folder so they survive being moved or deleted.
    private static func archiveFiles(_ files: [FileEntry], id: UUID, blobs: BlobStore, limit: Int64) -> [FileEntry] {
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        guard total <= limit else { return files }
        var result = files
        for (i, f) in files.enumerated() {
            let rel = "files/\(i)/\(f.name)"
            let dest = blobs.url(for: id, relative: rel)
            do {
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: f.originalURL, to: dest) // APFS clones are near-instant
                result[i].storedPath = rel
            } catch {
                NSLog("ClipboardCraft: could not archive \(f.originalPath): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// Large TIFFs (e.g. screenshots) are stored as PNG; TIFF is regenerated lazily on paste.
    private static func optimizedImageReps(_ items: [[(type: String, data: Data)]]) -> ([[(type: String, data: Data)]], (type: String, data: Data)?) {
        var out = items
        var primary: (type: String, data: Data)?
        for (i, reps) in items.enumerated() {
            let hasPNG = reps.contains { $0.type == PBType.png }
            if let tiffIndex = reps.firstIndex(where: { $0.type == PBType.tiff }), reps[tiffIndex].data.count > 1_000_000 {
                if hasPNG {
                    out[i].remove(at: tiffIndex)
                } else if let rep = NSBitmapImageRep(data: reps[tiffIndex].data),
                          let png = rep.representation(using: .png, properties: [:]), png.count < reps[tiffIndex].data.count {
                    out[i][tiffIndex] = (PBType.png, png)
                }
            }
        }
        for type in PBType.imageTypes {
            if let rep = out.lazy.flatMap({ $0 }).first(where: { $0.type == type }) { primary = rep; break }
        }
        return (out, primary)
    }

    static func writeThumbnail(from data: Data, to url: URL, maxPixel: Int = 480) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }
}
