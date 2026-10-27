import SwiftUI
import UniformTypeIdentifiers

/// Content preview shared by the quick panel and the library inspector.
struct ClipPreviewView: View {
    let item: ClipItem
    var compact = false

    var body: some View {
        switch item.kind {
        case .image: ImagePreview(item: item, compact: compact)
        case .text: TextPreview(item: item)
        case .richText: RichTextPreview(item: item)
        case .code: CodePreview(item: item, compact: compact)
        case .link: LinkPreview(item: item, compact: compact)
        case .color: ColorPreview(item: item, compact: compact)
        case .file: FilePreview(item: item, compact: compact)
        case .other: RawPreview(item: item)
        }
    }
}

// MARK: - Image

private struct ImagePreview: View {
    let item: ClipItem
    let compact: Bool
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .background(Checkerboard())
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    .padding(compact ? 18 : 12)
                    .onTapGesture(count: 2) { openInPreview() }
                    .onDrag { DragSupport.provider(for: item) }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            image = ThumbnailProvider.shared.cached(for: item, size: 240)
            image = await ThumbnailProvider.shared.image(for: item, size: compact ? 520 : 900) ?? image
        }
    }

    private func openInPreview() {
        guard let file = item.meta.imageFile else { return }
        NSWorkspace.shared.open(BlobStore.shared.url(for: item.id, relative: file))
    }
}

// MARK: - Text

private struct TextPreview: View {
    let item: ClipItem
    @State private var text: NSAttributedString?

    var body: some View {
        AttributedTextView(text: text ?? NSAttributedString())
            .task(id: item.contentHash + item.id.uuidString) {
                text = TextStyling.plain(item.text ?? "")
            }
    }
}

private struct RichTextPreview: View {
    let item: ClipItem
    @State private var text: NSAttributedString?

    var body: some View {
        AttributedTextView(text: text ?? NSAttributedString())
            .task(id: item.contentHash + item.id.uuidString) {
                text = TextStyling.richText(for: item) ?? TextStyling.plain(item.text ?? "")
            }
    }
}

private struct CodePreview: View {
    let item: ClipItem
    let compact: Bool
    @State private var text: NSAttributedString?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(.purple)
                Text(item.meta.codeLanguage ?? "Code").fontWeight(.semibold)
                Text("·").foregroundStyle(.tertiary)
                Text(Format.count(item.meta.lineCount ?? 1, "line")).foregroundStyle(.secondary)
                Spacer()
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider().opacity(0.6)
            AttributedTextView(text: text ?? NSAttributedString(), wraps: false)
        }
        .task(id: item.contentHash + (item.meta.codeLanguage ?? "")) {
            text = CodeHighlighter.highlight(item.text ?? "", language: item.meta.codeLanguage, fontSize: compact ? 12 : 12.5)
        }
    }
}

// MARK: - Link

private struct LinkPreview: View {
    let item: ClipItem
    let compact: Bool
    @State private var icon: NSImage?

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.blue.gradient.opacity(0.18))
                    .frame(width: 76, height: 76)
                if let icon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: 44, height: 44)
                } else {
                    Image(systemName: "globe").font(.system(size: 34, weight: .medium)).foregroundStyle(.blue.gradient)
                }
            }
            VStack(spacing: 5) {
                if let title = item.meta.linkTitle, !title.isEmpty {
                    Text(title).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.center).lineLimit(3)
                }
                Text(item.meta.urlHost ?? "").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Text(item.meta.url ?? item.text ?? "")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 3 : 6)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 20)
            Button {
                if let s = item.meta.url, let url = URL(string: s) { NSWorkspace.shared.open(url) }
            } label: {
                Label("Open Link", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            if let url = item.meta.url { icon = LinkPreviewProvider.shared.cachedIcon(for: url) }
            if icon == nil { icon = await LinkPreviewProvider.shared.fetch(for: item, store: AppServices.shared.store) }
        }
    }
}

// MARK: - Color

private struct ColorPreview: View {
    let item: ClipItem
    let compact: Bool

    var body: some View {
        if let c = ColorParser.parse(item.text ?? item.meta.colorHex ?? "") {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.clear).background(Checkerboard(square: 10))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(c.color)
                    Text(c.hex)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(c.isLight ? Color.black.opacity(0.75) : Color.white)
                }
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: c.color.opacity(0.45), radius: 18, y: 8)
                .frame(maxHeight: compact ? 150 : 200)

                VStack(spacing: 6) {
                    ColorValueRow(label: "HEX", value: c.hex)
                    ColorValueRow(label: "RGB", value: c.rgbString)
                    ColorValueRow(label: "HSL", value: c.hslString)
                    if !compact { ColorValueRow(label: "SwiftUI", value: c.swiftUIString) }
                }
            }
            .padding(compact ? 18 : 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ColorValueRow: View {
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        HStack {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(width: 54, alignment: .leading)
            Text(value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).lineLimit(1)
            Spacer()
            Button {
                AppServices.shared.paste.copyString(value)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Copy \(label)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Files

private struct FilePreview: View {
    let item: ClipItem
    let compact: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        let files = item.files
        if files.count == 1, let file = files.first {
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(nsImage: ThumbnailProvider.icon(for: file, in: item)).resizable().aspectRatio(contentMode: .fit)
                    }
                }
                .frame(maxWidth: compact ? 170 : 260, maxHeight: compact ? 170 : 260)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .onDrag { DragSupport.provider(for: item) }
                VStack(spacing: 4) {
                    Text(file.name).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2)
                    Text("\(file.typeDescription) · \(Format.bytes(file.size))").font(.system(size: 12)).foregroundStyle(.secondary)
                    FileStatusBadge(file: file, item: item)
                }
                .padding(.horizontal)
                FileActions(file: file, item: item)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: item.id) {
                thumbnail = await ThumbnailProvider.shared.image(for: item, size: compact ? 170 : 260)
            }
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                        HStack(spacing: 10) {
                            Image(nsImage: ThumbnailProvider.icon(for: file, in: item)).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text("\(file.typeDescription) · \(Format.bytes(file.size))").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            FileStatusBadge(file: file, item: item, iconOnly: true)
                            Button { reveal(file) } label: { Image(systemName: "arrow.right.circle") }
                                .buttonStyle(.borderless).help("Show in Finder")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(12)
            }
        }
    }

    private func reveal(_ file: FileEntry) {
        if let url = AppServices.shared.paste.resolvedURL(for: file, in: item) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

struct FileStatusBadge: View {
    let file: FileEntry
    let item: ClipItem
    var iconOnly = false

    var body: some View {
        let (text, symbol, color) = status
        if iconOnly {
            Image(systemName: symbol).foregroundStyle(color).help(text)
        } else {
            Label(text, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.12), in: Capsule())
        }
    }

    private var status: (String, String, Color) {
        let hasCopy = file.storedPath.map { FileManager.default.fileExists(atPath: BlobStore.shared.url(for: item.id, relative: $0).path) } ?? false
        if file.originalExists { return (hasCopy ? "Original · backup saved" : "Original available", "checkmark.circle.fill", .green) }
        if hasCopy { return ("Original moved · using saved copy", "archivebox.fill", .orange) }
        return ("File is missing", "exclamationmark.triangle.fill", .red)
    }
}

private struct FileActions: View {
    let file: FileEntry
    let item: ClipItem

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if let url = AppServices.shared.paste.resolvedURL(for: file, in: item) { NSWorkspace.shared.open(url) }
            } label: { Label("Open", systemImage: "arrow.up.forward.app") }
            Button {
                if let url = AppServices.shared.paste.resolvedURL(for: file, in: item) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } label: { Label("Show in Finder", systemImage: "folder") }
        }
        .buttonStyle(.glass)
    }
}

// MARK: - Raw

private struct RawPreview: View {
    let item: ClipItem

    var body: some View {
        let entries = BlobStore.shared.manifest(for: item.id)?.items.flatMap { $0 } ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Stored formats").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(entries, id: \.file) { e in
                    HStack {
                        Image(systemName: "shippingbox").foregroundStyle(.brown)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(UTType(e.type)?.localizedDescription ?? e.type).font(.system(size: 12.5, weight: .medium))
                            Text(e.type).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(Format.bytes(Int64(e.size))).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Drag support

extension UTType {
    static let clipID = UTType(exportedAs: "app.clipboardcraft.clip-id")
}

@MainActor
enum DragSupport {
    static func provider(for item: ClipItem) -> NSItemProvider {
        let provider = NSItemProvider()
        let idData = Data(item.id.uuidString.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.clipID.identifier, visibility: .ownProcess) { done in
            done(idData, nil); return nil
        }
        let paste = AppServices.shared.paste
        switch item.kind {
        case .file:
            if let url = paste.fileURLs(for: item).first {
                provider.registerFileRepresentation(forTypeIdentifier: item.files.first?.typeIdentifier ?? UTType.data.identifier,
                                                    fileOptions: [], visibility: .all) { done in
                    done(url, false, nil); return nil
                }
                provider.registerObject(url as NSURL, visibility: .all)
                provider.suggestedName = url.lastPathComponent
            }
        case .image:
            if let file = item.meta.imageFile {
                let url = BlobStore.shared.url(for: item.id, relative: file)
                let type = item.meta.imageType ?? UTType.png.identifier
                provider.registerFileRepresentation(forTypeIdentifier: type, fileOptions: [], visibility: .all) { done in
                    done(url, false, nil); return nil
                }
                provider.suggestedName = Exporter.suggestedName(for: item).0
            }
        case .link:
            if let s = item.meta.url, let url = URL(string: s) { provider.registerObject(url as NSURL, visibility: .all) }
            provider.registerObject((item.text ?? "") as NSString, visibility: .all)
        default:
            if let text = paste.textValue(of: item) { provider.registerObject(text as NSString, visibility: .all) }
        }
        return provider
    }
}
