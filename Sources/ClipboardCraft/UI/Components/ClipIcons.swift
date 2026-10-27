import SwiftUI

/// Leading tile for a clip: thumbnail, file icon, color swatch or a tinted symbol.
struct ClipIconView: View {
    let item: ClipItem
    var size: CGFloat = 34

    @State private var image: NSImage?
    @State private var favicon: NSImage?

    private var radius: CGFloat { size * 0.26 }

    var body: some View {
        ZStack {
            switch item.kind {
            case .image:
                thumbnailTile
            case .file:
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                } else if let file = item.files.first {
                    Image(nsImage: ThumbnailProvider.icon(for: file, in: item)).resizable().aspectRatio(contentMode: .fit)
                }
            case .color:
                let parsed = item.meta.colorHex.flatMap(ColorParser.parse)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(parsed?.color ?? .gray)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.primary.opacity(0.15), lineWidth: 1))
            case .link where favicon != nil:
                symbolBackground
                Image(nsImage: favicon!).resizable().aspectRatio(contentMode: .fit).padding(size * 0.2)
            default:
                symbolBackground
                Image(systemName: item.kind == .link ? "globe" : item.kind.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(item.kind.tint.gradient)
            }
        }
        .frame(width: size, height: size)
        .task(id: item.id) {
            if item.kind == .image || item.kind == .file {
                image = ThumbnailProvider.shared.cached(for: item, size: size)
                if image == nil { image = await ThumbnailProvider.shared.image(for: item, size: size) }
            } else if item.kind == .link, let url = item.meta.url {
                favicon = LinkPreviewProvider.shared.cachedIcon(for: url)
            }
        }
    }

    private var symbolBackground: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(item.kind.tint.opacity(0.16))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(item.kind.tint.opacity(0.18), lineWidth: 0.5))
    }

    @ViewBuilder private var thumbnailTile: some View {
        if let image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
        } else {
            symbolBackground
            Image(systemName: "photo").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(item.kind.tint)
        }
    }
}

struct AppIconView: View {
    let bundleID: String?
    var size: CGFloat = 14

    var body: some View {
        if let icon = AppIconCache.icon(for: bundleID) {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed").font(.system(size: size * 0.8)).frame(width: size, height: size)
        }
    }
}

/// A small key-cap glyph, e.g. ⌘1 or ↩.
struct KeyCap: View {
    let text: String
    var prominent = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(prominent ? .primary : .secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(.primary.opacity(prominent ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) { ForEach(keys, id: \.self) { KeyCap(text: $0) } }
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }
}

struct KindBadge: View {
    let kind: ClipKind
    var label: String?

    var body: some View {
        Label(label ?? kind.title, systemImage: kind.symbol)
            .font(.system(size: 10.5, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(kind.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(kind.tint.opacity(0.13), in: Capsule())
    }
}

struct CollectionDot: View {
    let collection: ClipCollection
    var body: some View {
        Circle().fill(collection.color.color.gradient).frame(width: 7, height: 7)
            .help(collection.name)
    }
}

/// Transparent-image backdrop.
struct Checkerboard: View {
    var square: CGFloat = 8
    var body: some View {
        Canvas { ctx, size in
            let cols = Int(ceil(size.width / square)), rows = Int(ceil(size.height / square))
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * square, y: CGFloat(r) * square, width: square, height: square)),
                             with: .color(.primary.opacity(0.06)))
                }
            }
        }
    }
}

struct ToastView: View {
    let toast: Toast
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol).foregroundStyle(.tint)
            Text(toast.message).lineLimit(1)
            if toast.undoIDs != nil, let onUndo {
                Divider().frame(height: 14)
                Button("Undo", action: onUndo)
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                KeyCap(text: "⌘Z")
            }
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

extension View {
    /// Shows the store's toast at the bottom of the view.
    func toastOverlay(_ store: ClipStore, bottomPadding: CGFloat = 16) -> some View {
        overlay(alignment: .bottom) {
            if let toast = store.toast {
                ToastView(toast: toast, onUndo: toast.undoIDs.map { ids in { store.restore(ids) } })
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                    .id(toast.id)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.toast)
    }
}
