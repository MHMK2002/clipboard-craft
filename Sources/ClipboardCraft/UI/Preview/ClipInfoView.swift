import SwiftUI
import UniformTypeIdentifiers

/// Key/value metadata about a clip.
struct ClipInfoView: View {
    let item: ClipItem
    var compact = false

    var body: some View {
        let now = Ticker.shared.now
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: compact ? 5 : 8) {
            row("Source") {
                HStack(spacing: 5) {
                    AppIconView(bundleID: item.sourceBundleID, size: 14)
                    Text(item.sourceAppName ?? "Unknown")
                }
            }
            row("Copied") { Text("\(Format.relative(item.updatedAt, now: now)) · \(Format.dateTime(item.updatedAt))") }
            if !compact, item.createdAt != item.updatedAt {
                row("First copied") { Text(Format.dateTime(item.createdAt)) }
            }
            if item.copyCount > 1 { row("Times copied") { Text("\(item.copyCount)") } }
            ForEach(Array(kindRows.enumerated()), id: \.offset) { _, pair in
                row(pair.0) { Text(pair.1).textSelection(.enabled) }
            }
            if !compact || item.byteSize > 0 { row("Storage") { Text(Format.bytes(item.byteSize)) } }
        }
        .font(.system(size: compact ? 11.5 : 12))
    }

    private var kindRows: [(String, String)] {
        let m = item.meta
        switch item.kind {
        case .text, .richText, .code:
            var rows = [("Content", "\(Format.count(m.charCount ?? 0, "character")) · \(Format.count(m.wordCount ?? 0, "word")) · \(Format.count(m.lineCount ?? 1, "line"))")]
            if item.kind == .code { rows.insert(("Language", m.codeLanguage ?? "Code"), at: 0) }
            if item.kind == .richText { rows.append(("Format", (m.richType ?? "rtf").uppercased())) }
            if m.edited == true { rows.append(("Edited", "Yes")) }
            return rows
        case .image:
            var rows: [(String, String)] = []
            if let w = m.imageWidth, let h = m.imageHeight { rows.append(("Dimensions", "\(w) × \(h) px")) }
            if let t = m.imageType { rows.append(("Format", UTType(t)?.localizedDescription ?? t)) }
            return rows
        case .link:
            return [("Domain", m.urlHost ?? "—")]
        case .color:
            return [("Value", m.colorHex ?? item.text ?? "")]
        case .file:
            let files = item.files
            if files.count == 1, let f = files.first {
                return [("Kind", f.typeDescription), ("Size", Format.bytes(f.size)), ("Path", Format.abbreviatedPath(f.originalPath))]
            }
            let total = files.reduce(Int64(0)) { $0 + $1.size }
            return [("Items", "\(files.count)"), ("Total size", Format.bytes(total))]
        case .other:
            return [("Formats", (m.types ?? []).joined(separator: ", "))]
        }
    }

    private func row(_ label: String, @ViewBuilder _ value: () -> some View) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value().foregroundStyle(.primary).lineLimit(compact ? 1 : 3)
        }
    }
}
