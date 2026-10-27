import AppKit
import UniformTypeIdentifiers

/// Saving clips to disk.
@MainActor
enum Exporter {
    static func export(_ items: [ClipItem], paste: PasteService) {
        if items.count == 1 { exportSingle(items[0], paste: paste) } else if !items.isEmpty { exportMany(items, paste: paste) }
    }

    private static func exportSingle(_ item: ClipItem, paste: PasteService) {
        if item.kind == .file {
            exportMany([item], paste: paste)
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let (name, types) = suggestedName(for: item)
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = types
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try write(item, to: url, paste: paste)
            AppServices.shared.store.showToast("Exported \(url.lastPathComponent)", symbol: "square.and.arrow.up.fill")
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private static func exportMany(_ items: [ClipItem], paste: PasteService) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder to export \(items.count == 1 ? "the files" : "\(items.count) items") to."
        NSApp.activate()
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        var count = 0
        for item in items {
            if item.kind == .file {
                for f in item.files {
                    guard let src = paste.resolvedURL(for: f, in: item) else { continue }
                    let dest = uniqueURL(folder.appendingPathComponent(f.name))
                    if (try? FileManager.default.copyItem(at: src, to: dest)) != nil { count += 1 }
                }
            } else {
                let (name, _) = suggestedName(for: item)
                if (try? write(item, to: uniqueURL(folder.appendingPathComponent(name)), paste: paste)) != nil { count += 1 }
            }
        }
        AppServices.shared.store.showToast("Exported \(count) \(count == 1 ? "file" : "files")", symbol: "square.and.arrow.up.fill")
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    static func suggestedName(for item: ClipItem) -> (String, [UTType]) {
        let base = sanitize(item.kind == .image ? "Image \(Format.dateTime(item.createdAt))" : item.displayTitle)
        switch item.kind {
        case .image:
            let ext = item.meta.imageFile.map { ($0 as NSString).pathExtension } ?? "png"
            return ("\(base).\(ext)", [.png, .jpeg, .tiff, .heic])
        case .richText:
            return ("\(base).rtf", [.rtf, .plainText])
        case .code:
            let ext = CodeLanguage.named(item.meta.codeLanguage).fileExtension
            return ("\(base).\(ext)", [UTType(filenameExtension: ext) ?? .sourceCode, .plainText])
        case .link:
            return ("\(base).webloc", [UTType(filenameExtension: "webloc") ?? .data, .plainText])
        case .other:
            let type = item.meta.types?.first.flatMap(UTType.init)
            return ("\(base).\(type?.preferredFilenameExtension ?? "data")", [type ?? .data])
        default:
            return ("\(base).txt", [.plainText])
        }
    }

    private static func write(_ item: ClipItem, to url: URL, paste: PasteService) throws {
        let blobs = BlobStore.shared
        let ext = url.pathExtension.lowercased()
        switch item.kind {
        case .image:
            guard let file = item.meta.imageFile, let image = NSImage(contentsOf: blobs.url(for: item.id, relative: file)),
                  let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { throw CocoaError(.fileReadCorruptFile) }
            let type: NSBitmapImageRep.FileType = switch ext {
            case "jpg", "jpeg": .jpeg
            case "tif", "tiff": .tiff
            default: .png
            }
            let data: Data?
            if ext == "heic", let cg = rep.cgImage {
                let out = NSMutableData()
                if let dest = CGImageDestinationCreateWithData(out, UTType.heic.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(dest, cg, nil)
                    CGImageDestinationFinalize(dest)
                }
                data = out as Data
            } else {
                data = rep.representation(using: type, properties: [.compressionFactor: 0.9])
            }
            try data?.write(to: url, options: .atomic)
        case .richText where ext == "rtf":
            if let rtf = blobs.repData(for: item.id, type: PBType.rtf) {
                try rtf.write(to: url, options: .atomic)
            } else {
                try (item.text ?? "").write(to: url, atomically: true, encoding: .utf8)
            }
        case .link where ext == "webloc":
            let plist = ["URL": item.meta.url ?? item.text ?? ""]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
        case .other:
            if let type = item.meta.types?.first, let data = blobs.repData(for: item.id, type: type) {
                try data.write(to: url, options: .atomic)
            }
        default:
            try (paste.textValue(of: item) ?? "").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func sanitize(_ s: String) -> String {
        let cleaned = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let short = String(cleaned.prefix(60))
        return short.isEmpty ? "Clip" : short
    }

    private static func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var n = 2
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            n += 1
        }
        return candidate
    }
}

/// Importing content dropped onto the library window or chosen in an open panel.
@MainActor
enum Importer {
    static let dropTypes: [UTType] = [.fileURL, .image, .url, .utf8PlainText, .plainText]

    static func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var s = PasteboardSnapshot(items: [], fileURLs: urls)
        s.sourceAppName = "Imported"
        AppServices.shared.monitor.ingest(s)
    }

    static func chooseFilesToImport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Import"
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    static func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        var fileURLs: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { lock.lock(); fileURLs.append(url); lock.unlock() }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.png.identifier
                provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                    guard let data else { return }
                    let pbType = PBType.imageTypes.contains(type) ? type : PBType.png
                    DispatchQueue.main.async { ingest([(pbType, data)]) }
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let s = url.absoluteString
                    DispatchQueue.main.async { ingest([(PBType.url, Data(s.utf8)), (PBType.plainText, Data(s.utf8))]) }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                handled = true
                _ = provider.loadObject(ofClass: String.self) { str, _ in
                    guard let str else { return }
                    DispatchQueue.main.async { ingest([(PBType.plainText, Data(str.utf8))]) }
                }
            }
        }
        group.notify(queue: .main) {
            if !fileURLs.isEmpty { importFiles(fileURLs) }
        }
        return handled
    }

    private static func ingest(_ reps: [(type: String, data: Data)]) {
        var s = PasteboardSnapshot(items: [reps], fileURLs: [])
        s.sourceAppName = "Imported"
        AppServices.shared.monitor.ingest(s)
    }
}
