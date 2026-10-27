import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Kind

enum ClipKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case text, richText, link, code, color, image, file, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .richText: "Rich Text"
        case .link: "Link"
        case .code: "Code"
        case .color: "Color"
        case .image: "Image"
        case .file: "File"
        case .other: "Other"
        }
    }

    var pluralTitle: String {
        switch self {
        case .text: "Text"
        case .richText: "Rich Text"
        case .link: "Links"
        case .code: "Code"
        case .color: "Colors"
        case .image: "Images"
        case .file: "Files"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .link: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .color: "paintpalette.fill"
        case .image: "photo"
        case .file: "doc.fill"
        case .other: "shippingbox.fill"
        }
    }

    var tint: Color {
        switch self {
        case .text: Color(red: 0.45, green: 0.50, blue: 0.58)
        case .richText: .orange
        case .link: .blue
        case .code: .purple
        case .color: .pink
        case .image: .green
        case .file: .teal
        case .other: .brown
        }
    }

    /// Kinds whose content is primarily a string.
    var isTextual: Bool {
        switch self {
        case .text, .richText, .link, .code, .color: true
        case .image, .file, .other: false
        }
    }

    /// Search tokens accepted by `type:` filters.
    var searchAliases: [String] {
        switch self {
        case .text: ["text", "txt", "plain"]
        case .richText: ["rich", "richtext", "rtf", "html"]
        case .link: ["link", "links", "url", "urls"]
        case .code: ["code", "snippet"]
        case .color: ["color", "colors", "colour"]
        case .image: ["image", "images", "img", "photo", "picture"]
        case .file: ["file", "files", "doc"]
        case .other: ["other", "data", "raw"]
        }
    }
}

// MARK: - Files

struct FileEntry: Codable, Hashable, Sendable {
    var name: String
    var originalPath: String
    /// Path of the archived copy, relative to the clip's blob folder.
    var storedPath: String?
    var size: Int64
    var typeIdentifier: String?
    var isDirectory: Bool
    var modifiedAt: Date?

    var originalURL: URL { URL(fileURLWithPath: originalPath) }

    var originalExists: Bool { FileManager.default.fileExists(atPath: originalPath) }

    var utType: UTType? { typeIdentifier.flatMap(UTType.init) }

    var typeDescription: String {
        if isDirectory { return "Folder" }
        return utType?.localizedDescription ?? (name as NSString).pathExtension.uppercased()
    }
}

// MARK: - Metadata

struct ClipMeta: Codable, Hashable, Sendable {
    var files: [FileEntry]?
    var imageWidth: Int?
    var imageHeight: Int?
    var imageType: String?
    /// File name (inside the clip folder) of the primary image.
    var imageFile: String?
    var colorHex: String?
    var codeLanguage: String?
    var url: String?
    var urlHost: String?
    var linkTitle: String?
    var richType: String?
    var types: [String]?
    var charCount: Int?
    var lineCount: Int?
    var wordCount: Int?
    var edited: Bool?
}

// MARK: - Clip

struct ClipItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var kind: ClipKind
    var createdAt: Date
    var updatedAt: Date
    var copyCount: Int
    var title: String
    var text: String?
    var contentHash: String
    var sourceBundleID: String?
    var sourceAppName: String?
    var isPinned: Bool
    var isFavorite: Bool
    var byteSize: Int64
    var meta: ClipMeta
    var collectionIDs: Set<UUID>
    var searchKey: String = ""

    /// Items that are protected from automatic clean-up.
    var isProtected: Bool { isPinned || isFavorite || !collectionIDs.isEmpty }

    var files: [FileEntry] { meta.files ?? [] }

    var displayTitle: String {
        switch kind {
        case .image:
            if let w = meta.imageWidth, let h = meta.imageHeight { return "Image \(w) × \(h)" }
            return "Image"
        case .file:
            let files = self.files
            if files.count == 1 { return files[0].name }
            if let first = files.first { return "\(first.name) + \(files.count - 1) more" }
            return title
        case .link:
            if let t = meta.linkTitle, !t.isEmpty { return t }
            return title
        case .color:
            return meta.colorHex ?? title
        default:
            return title.isEmpty ? "(empty)" : title
        }
    }

    /// A short, kind-specific summary used in list subtitles.
    var detailSummary: String {
        switch kind {
        case .text, .richText:
            let chars = meta.charCount ?? text?.count ?? 0
            let lines = meta.lineCount ?? 1
            return lines > 1 ? "\(lines) lines" : Format.count(chars, "char")
        case .code:
            let lang = meta.codeLanguage ?? "Code"
            let lines = meta.lineCount ?? 1
            return "\(lang) · \(lines) \(lines == 1 ? "line" : "lines")"
        case .link:
            return meta.urlHost ?? "Link"
        case .color:
            return "Color"
        case .image:
            let fmt = meta.imageType.flatMap { UTType($0)?.preferredFilenameExtension?.uppercased() } ?? "Image"
            return "\(fmt) · \(Format.bytes(byteSize))"
        case .file:
            let total = files.reduce(Int64(0)) { $0 + $1.size }
            let n = files.count
            return n == 1 ? Format.bytes(total) : "\(n) items · \(Format.bytes(total))"
        case .other:
            return meta.types?.first ?? "Data"
        }
    }
}

// MARK: - Collections

enum CollectionColor: String, CaseIterable, Codable, Identifiable {
    case blue, indigo, purple, pink, red, orange, yellow, green, teal, gray
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .gray: .gray
        }
    }
}

struct ClipCollection: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var symbol: String
    var color: CollectionColor
    var sortOrder: Int

    static let symbolChoices = [
        "folder.fill", "briefcase.fill", "person.fill", "house.fill", "chevron.left.forwardslash.chevron.right",
        "magnifyingglass", "book.fill", "graduationcap.fill", "star.fill", "heart.fill", "bolt.fill",
        "lightbulb.fill", "paintbrush.pointed.fill", "photo.fill", "link", "doc.text.fill", "cart.fill",
        "airplane", "gamecontroller.fill", "music.note", "leaf.fill", "flame.fill", "tag.fill", "tray.full.fill"
    ]
}

// MARK: - Pasteboard representations

struct RepEntry: Codable, Hashable {
    var type: String
    var file: String
    var size: Int
}

struct RepManifest: Codable {
    var items: [[RepEntry]]
}

/// Well-known pasteboard type identifiers.
enum PBType {
    static let plainText = "public.utf8-plain-text"
    static let utf16Text = "public.utf16-plain-text"
    static let legacyString = "NSStringPboardType"
    static let rtf = "public.rtf"
    static let rtfd = "com.apple.flat-rtfd"
    static let html = "public.html"
    static let url = "public.url"
    static let urlName = "public.url-name"
    static let fileURL = "public.file-url"
    static let png = "public.png"
    static let tiff = "public.tiff"
    static let jpeg = "public.jpeg"
    static let heic = "public.heic"
    static let gif = "com.compuserve.gif"
    static let webp = "org.webmproject.webp"
    static let bmp = "com.microsoft.bmp"
    static let pdf = "com.adobe.pdf"
    static let own = "app.clipboardcraft.own"

    static let imageTypes = [png, tiff, jpeg, heic, gif, webp, bmp]

    /// Markers that signal the content must not be recorded (password managers etc.).
    /// See http://nspasteboard.org
    static let privacyMarkers: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType",
        "com.typeit4me.clipping",
        "Pasteboard generator type",
        "net.antelle.keeweb"
    ]

    /// Types never worth persisting.
    static let skipped: Set<String> = [
        own,
        "com.apple.pasteboard.promised-file-url",
        "com.apple.pasteboard.promised-file-content-type",
        "com.apple.NSFilePromiseItemMetaData",
        "com.apple.pasteboard.promised-suggested-file-name",
        "NSPromiseContentsPboardType"
    ]
}
