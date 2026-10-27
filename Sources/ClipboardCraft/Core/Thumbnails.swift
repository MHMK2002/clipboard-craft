import AppKit
import ImageIO
import LinkPresentation
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Loads and caches images used for clip previews.
@MainActor
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()
    private let cache = NSCache<NSString, NSImage>()
    private let blobs = BlobStore.shared

    private init() { cache.countLimit = 400 }

    private func key(_ id: UUID, _ size: CGFloat) -> NSString { "\(id.uuidString)-\(Int(size))" as NSString }

    func cached(for item: ClipItem, size: CGFloat) -> NSImage? { cache.object(forKey: key(item.id, size)) }

    /// `size` is in points; larger sizes load the full image.
    func image(for item: ClipItem, size: CGFloat) async -> NSImage? {
        let k = key(item.id, size)
        if let hit = cache.object(forKey: k) { return hit }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = Int(size * scale)
        var result: NSImage?
        switch item.kind {
        case .image:
            let thumb = blobs.thumbnailURL(for: item.id)
            let full = item.meta.imageFile.map { blobs.url(for: item.id, relative: $0) }
            let source = (pixels <= 480 && FileManager.default.fileExists(atPath: thumb.path)) ? thumb : (full ?? thumb)
            result = await Self.downsample(source, maxPixel: max(pixels, 64))
        case .file:
            guard let file = item.files.first else { return nil }
            let url = file.originalExists ? file.originalURL : file.storedPath.map { blobs.url(for: item.id, relative: $0) }
            if let url { result = await Self.quickLook(url, size: size, scale: scale) }
            if result == nil { result = Self.icon(for: file, in: item) }
        default:
            return nil
        }
        if let result { cache.setObject(result, forKey: k) }
        return result
    }

    func icon(for file: FileEntry, in item: ClipItem) -> NSImage {
        Self.icon(for: file, in: item)
    }

    static func icon(for file: FileEntry, in item: ClipItem) -> NSImage {
        if file.originalExists { return NSWorkspace.shared.icon(forFile: file.originalPath) }
        if let stored = file.storedPath {
            let path = BlobStore.shared.url(for: item.id, relative: stored).path
            if FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
        }
        return NSWorkspace.shared.icon(for: file.utType ?? (file.isDirectory ? .folder : .data))
    }

    nonisolated static func downsample(_ url: URL, maxPixel: Int) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
    }

    nonisolated static func quickLook(_ url: URL, size: CGFloat, scale: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: scale,
                                                   representationTypes: .thumbnail)
        return await withCheckedContinuation { cont in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                cont.resume(returning: rep?.nsImage)
            }
        }
    }
}

/// Icons of source applications.
@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

/// Fetches link titles and icons (opt-in, because it contacts the website).
@MainActor
final class LinkPreviewProvider {
    static let shared = LinkPreviewProvider()
    private var icons: [String: NSImage] = [:]
    private var inFlight = Set<String>()

    func cachedIcon(for url: String) -> NSImage? { icons[url] }

    func fetch(for item: ClipItem, store: ClipStore) async -> NSImage? {
        guard AppSettings.shared.loadLinkPreviews, let s = item.meta.url, let url = URL(string: s),
              url.scheme?.hasPrefix("http") == true else { return nil }
        if let icon = icons[s] { return icon }
        guard !inFlight.contains(s) else { return nil }
        inFlight.insert(s)
        defer { inFlight.remove(s) }
        let provider = LPMetadataProvider()
        provider.timeout = 8
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return nil }
        if let title = metadata.title, !title.isEmpty, item.meta.linkTitle != title {
            store.setLinkTitle(item.id, title)
        }
        guard let iconProvider = metadata.iconProvider ?? metadata.imageProvider else { return nil }
        let image: NSImage? = await withCheckedContinuation { cont in
            _ = iconProvider.loadObject(ofClass: NSImage.self) { obj, _ in
                cont.resume(returning: obj as? NSImage)
            }
        }
        if let image { icons[s] = image }
        return image
    }
}
