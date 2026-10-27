import Foundation

enum Format {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Compact relative time: "now", "4m", "2h", "Yesterday", "Mon", "12 Oct".
    static func shortRelative(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 45 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "\(Int(seconds / 3600))h" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if seconds < 6 * 86_400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        if cal.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
    }

    static func relative(_ date: Date, now: Date = .now) -> String {
        if now.timeIntervalSince(date) < 45 { return "just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    static func count(_ n: Int, _ noun: String) -> String {
        "\(n.formatted()) \(n == 1 ? noun : noun + "s")"
    }

    /// Human size for a limit expressed in MB ("512 MB", "2 GB").
    static func megabytes(_ mb: Int) -> String {
        mb >= 1024 ? "\((Double(mb) / 1024).formatted(.number.precision(.fractionLength(0...1)))) GB" : "\(mb) MB"
    }

    static func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

enum SearchFold {
    /// Normalises text for searching: case / diacritic / width insensitive, plus
    /// Persian/Arabic letter unification and zero-width-joiner removal.
    static func fold(_ s: String) -> String {
        var out = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        if out.unicodeScalars.contains(where: { $0.value >= 0x0600 && $0.value <= 0x06FF || $0.value == 0x200C || $0.value == 0x200D }) {
            out = String(String.UnicodeScalarView(out.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
                switch scalar.value {
                case 0x200C, 0x200D: return nil // ZWNJ / ZWJ
                case 0x064A, 0x0649: return Unicode.Scalar(0x06CC) // ي ى → ی
                case 0x0643: return Unicode.Scalar(0x06A9) // ك → ک
                case 0x0629: return Unicode.Scalar(0x0647) // ة → ه
                case 0x0623, 0x0625, 0x0622: return Unicode.Scalar(0x0627) // أ إ آ → ا
                case 0x0660...0x0669: return Unicode.Scalar(scalar.value - 0x0660 + 0x30) // Arabic digits
                case 0x06F0...0x06F9: return Unicode.Scalar(scalar.value - 0x06F0 + 0x30) // Persian digits
                default: return scalar
                }
            }))
        }
        return out
    }

    static func searchKey(for item: ClipItem) -> String {
        var parts: [String] = [item.title]
        if let text = item.text { parts.append(String(text.prefix(30_000))) }
        if let app = item.sourceAppName { parts.append(app) }
        let m = item.meta
        if let files = m.files {
            for f in files { parts.append(f.name); parts.append(f.originalPath) }
        }
        [m.url, m.urlHost, m.linkTitle, m.colorHex, m.codeLanguage].compactMap { $0 }.forEach { parts.append($0) }
        return fold(parts.joined(separator: "\n"))
    }
}
