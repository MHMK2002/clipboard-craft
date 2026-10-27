import AppKit
import SwiftUI

/// Read-only, selectable, scrollable attributed text (handles RTL/bidi and large content well).
struct AttributedTextView: NSViewRepresentable {
    let text: NSAttributedString
    var inset: CGSize = CGSize(width: 14, height: 12)
    var wraps = true

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = inset
        tv.isRichText = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        configureWrapping(tv, scroll: scroll)
        tv.textStorage?.setAttributedString(text)
        context.coordinator.last = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if context.coordinator.last !== text {
            tv.textStorage?.setAttributedString(text)
            context.coordinator.last = text
            tv.scroll(.zero)
        }
    }

    private func configureWrapping(_ tv: NSTextView, scroll: NSScrollView) {
        if wraps { return }
        scroll.hasHorizontalScroller = true
        tv.isHorizontallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var last: NSAttributedString? }
}

enum TextStyling {
    static func plain(_ s: String, size: CGFloat = 13) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .natural
        para.baseWritingDirection = .natural
        para.lineSpacing = 2.5
        return NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para
        ])
    }

    /// Loads stored rich text and adapts neutral colors so it stays legible in dark mode.
    @MainActor
    static func richText(for item: ClipItem) -> NSAttributedString? {
        let blobs = BlobStore.shared
        var result: NSAttributedString?
        if let rtf = blobs.repData(for: item.id, type: PBType.rtf) {
            result = NSAttributedString(rtf: rtf, documentAttributes: nil)
        } else if let rtfd = blobs.repData(for: item.id, type: PBType.rtfd) {
            result = NSAttributedString(rtfd: rtfd, documentAttributes: nil)
        } else if let html = blobs.repData(for: item.id, type: PBType.html), html.count < 600_000 {
            result = NSAttributedString(html: html, documentAttributes: nil)
        }
        return result.map(adapt)
    }

    static func adapt(_ a: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: a)
        let full = NSRange(location: 0, length: m.length)
        m.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            guard let c = (value as? NSColor)?.usingColorSpace(.sRGB) else {
                m.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                return
            }
            if isNeutral(c) { m.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range) }
        }
        m.enumerateAttribute(.backgroundColor, in: full) { value, range, _ in
            if let c = (value as? NSColor)?.usingColorSpace(.sRGB), isNeutral(c) { m.removeAttribute(.backgroundColor, range: range) }
        }
        return m
    }

    private static func isNeutral(_ c: NSColor) -> Bool {
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let spread = max(r, g, b) - min(r, g, b)
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return spread < 0.12 && (lum < 0.3 || lum > 0.85)
    }
}
