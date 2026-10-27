import AppKit

// MARK: - Language specs

struct CodeLanguage: Sendable {
    let name: String
    let fileExtension: String
    let keywords: Set<String>
    let lineComments: [String]
    let blockComment: (String, String)?
    let quotes: Set<Character>
    let isMarkup: Bool

    init(_ name: String, ext: String, keywords: String, lineComments: [String] = ["//"],
         blockComment: (String, String)? = ("/*", "*/"), quotes: Set<Character> = ["\"", "'"], isMarkup: Bool = false) {
        self.name = name
        self.fileExtension = ext
        self.keywords = Set(keywords.split(separator: " ").map(String.init))
        self.lineComments = lineComments
        self.blockComment = blockComment
        self.quotes = quotes
        self.isMarkup = isMarkup
    }

    static let all: [String: CodeLanguage] = {
        let list: [CodeLanguage] = [
            CodeLanguage("Swift", ext: "swift", keywords: "func let var if else guard return import struct class enum protocol extension case switch default for in while repeat break continue where throws throw try catch do defer async await actor some any self Self init deinit static private fileprivate internal public open final override mutating nil true false is as inout lazy weak unowned subscript typealias associatedtype get set willSet didSet operator"),
            CodeLanguage("Python", ext: "py", keywords: "def class if elif else for while return import from as with try except finally raise pass break continue lambda yield global nonlocal assert del in is not and or None True False self async await match case print", lineComments: ["#"], blockComment: nil),
            CodeLanguage("JavaScript", ext: "js", keywords: "function const let var if else return for while do switch case default break continue new this class extends super import export from as async await try catch finally throw typeof instanceof in of null undefined true false yield delete void static get set", quotes: ["\"", "'", "`"]),
            CodeLanguage("TypeScript", ext: "ts", keywords: "function const let var if else return for while do switch case default break continue new this class extends implements super import export from as async await try catch finally throw typeof instanceof in of null undefined true false interface type enum public private protected readonly abstract declare namespace keyof string number boolean any unknown never void static", quotes: ["\"", "'", "`"]),
            CodeLanguage("Java", ext: "java", keywords: "public private protected class interface enum extends implements static final void int long double float boolean char byte short new return if else for while do switch case default break continue try catch finally throw throws import package this super null true false abstract synchronized var record"),
            CodeLanguage("Kotlin", ext: "kt", keywords: "fun val var class object interface data sealed enum if else when for while do return import package this super null true false is as in out override open private public internal protected suspend companion init lateinit by"),
            CodeLanguage("C", ext: "c", keywords: "int char float double void long short unsigned signed struct union enum typedef const static extern return if else for while do switch case default break continue sizeof goto NULL include define ifdef ifndef endif"),
            CodeLanguage("C++", ext: "cpp", keywords: "int char float double void long short unsigned signed struct union enum typedef const static extern return if else for while do switch case default break continue sizeof class public private protected virtual override template typename namespace using new delete this nullptr true false auto constexpr include define std"),
            CodeLanguage("C#", ext: "cs", keywords: "using namespace class interface struct enum public private protected internal static readonly const void int string bool var new return if else for foreach while do switch case default break continue try catch finally throw async await this base null true false override virtual abstract sealed get set"),
            CodeLanguage("Go", ext: "go", keywords: "package import func var const type struct interface map chan go defer return if else for range switch case default break continue select nil true false make new len append err"),
            CodeLanguage("Rust", ext: "rs", keywords: "fn let mut const static struct enum impl trait pub use mod crate self Self super match if else for while loop return break continue as in ref move async await dyn where unsafe true false Some None Ok Err"),
            CodeLanguage("Ruby", ext: "rb", keywords: "def class module if elsif else unless case when while until for in do end return yield begin rescue ensure raise require include extend self nil true false puts attr_accessor", lineComments: ["#"], blockComment: nil),
            CodeLanguage("PHP", ext: "php", keywords: "function class public private protected static return if else elseif foreach for while echo new this null true false array use namespace require include", lineComments: ["//", "#"]),
            CodeLanguage("Shell", ext: "sh", keywords: "if then else elif fi for in do done while case esac function return export local echo cd sudo source alias unset exit set", lineComments: ["#"], blockComment: nil),
            CodeLanguage("SQL", ext: "sql", keywords: "select from where insert into values update set delete create table index view drop alter add join left right inner outer on group by order having limit offset as and or not null is in like between distinct union all primary key foreign references default case when then else end count sum avg min max", lineComments: ["--"]),
            CodeLanguage("CSS", ext: "css", keywords: "important media import keyframes from to root", lineComments: [], blockComment: ("/*", "*/")),
            CodeLanguage("HTML", ext: "html", keywords: "", lineComments: [], blockComment: ("<!--", "-->"), isMarkup: true),
            CodeLanguage("XML", ext: "xml", keywords: "", lineComments: [], blockComment: ("<!--", "-->"), isMarkup: true),
            CodeLanguage("JSON", ext: "json", keywords: "true false null", lineComments: [], blockComment: nil, quotes: ["\""]),
            CodeLanguage("YAML", ext: "yaml", keywords: "true false null yes no", lineComments: ["#"], blockComment: nil),
            CodeLanguage("Code", ext: "txt", keywords: "func function def class if else return import let var const for while switch case public private static struct enum true false null nil new this self try catch")
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0) })
    }()

    static func named(_ name: String?) -> CodeLanguage {
        all[name ?? ""] ?? all["Code"]!
    }
}

// MARK: - Detection

enum CodeDetector {
    private struct Rule {
        let regex: NSRegularExpression
        let weight: Int
        init(_ pattern: String, _ weight: Int, caseInsensitive: Bool = false) {
            var opts: NSRegularExpression.Options = [.anchorsMatchLines]
            if caseInsensitive { opts.insert(.caseInsensitive) }
            regex = try! NSRegularExpression(pattern: pattern, options: opts)
            self.weight = weight
        }
    }

    private static let jsRules: [Rule] = [
        Rule(#"\b(const|let)\s+\w+\s*="#, 2),
        Rule(#"=>"#, 2),
        Rule(#"\bfunction\s*\w*\s*\("#, 3),
        Rule(#"\bconsole\.(log|error|warn)\("#, 4),
        Rule(#"\b(document|window)\.\w+"#, 3),
        Rule(#"\brequire\(['"]"#, 4),
        Rule(#"^\s*export\s+(default|const|function|class)\b"#, 3),
        Rule(#"^\s*import\s+.*\s+from\s+['"]"#, 4),
        Rule(#"===|!=="#, 3)
    ]

    private static let cRules: [Rule] = [
        Rule(#"#include\s*[<"]"#, 5),
        Rule(#"\bint\s+main\s*\("#, 4),
        Rule(#"\bprintf\s*\("#, 2),
        Rule(#"^\s*(void|int|char|float|double|unsigned|static)\s+\*?\w+\s*\("#, 2)
    ]

    private static let languages: [(String, [Rule])] = [
        ("Swift", [
            Rule(#"\bfunc\s+\w+\s*[(<]"#, 3),
            Rule(#"\bguard\b.*\belse\b"#, 3),
            Rule(#"\bimport\s+(SwiftUI|Foundation|UIKit|AppKit|Combine|Observation)\b"#, 5),
            Rule(#"@(State|Published|Observable|MainActor|Binding|objc|escaping|Environment)\b"#, 4),
            Rule(#"\b(if|guard)\s+let\b"#, 3),
            Rule(#"\b(struct|extension|protocol)\s+\w+"#, 2),
            Rule(#"\)\s*->\s*\w+"#, 2),
            Rule(#"\b(let|var)\s+\w+\s*:\s*\[?[A-Z]\w*"#, 2)
        ]),
        ("Python", [
            Rule(#"^\s*def\s+\w+\(.*\)\s*(->\s*[\w\[\], .]+)?:\s*$"#, 4),
            Rule(#"^\s*from\s+[\w.]+\s+import\s+"#, 4),
            Rule(#"^\s*import\s+[\w.]+(\s+as\s+\w+)?\s*$"#, 2),
            Rule(#"\bself\.\w+"#, 2),
            Rule(#"^\s*(elif|except|finally|else)\b.*:\s*$"#, 3),
            Rule(#"^\s*class\s+\w+(\(.*\))?:\s*$"#, 4),
            Rule(#"\bprint\("#, 1),
            Rule(#"^\s*(if|for|while|with)\s.*:\s*$"#, 1),
            Rule(#"\b(None|True|False)\b"#, 1)
        ]),
        ("JavaScript", jsRules),
        ("TypeScript", jsRules + [
            Rule(#":\s*(string|number|boolean|any|void|unknown)\b"#, 4),
            Rule(#"^\s*(export\s+)?(interface|type)\s+\w+"#, 4)
        ]),
        ("Java", [
            Rule(#"\bpublic\s+(static\s+)?(final\s+)?(class|void|int|String)\b"#, 4),
            Rule(#"System\.out\.print"#, 5),
            Rule(#"\bprivate\s+(final\s+)?\w+(<[\w, ]+>)?\s+\w+\s*[;=]"#, 3),
            Rule(#"@Override"#, 4)
        ]),
        ("Kotlin", [
            Rule(#"\bfun\s+\w+\s*\("#, 4),
            Rule(#"\bval\s+\w+\s*[:=]"#, 3),
            Rule(#"\bdata\s+class\b"#, 4),
            Rule(#"\bprintln\("#, 1)
        ]),
        ("C", cRules),
        ("C++", cRules + [
            Rule(#"\bstd::\w+"#, 5),
            Rule(#"\b(cout|cin|endl)\b"#, 4),
            Rule(#"\btemplate\s*<"#, 5)
        ]),
        ("C#", [
            Rule(#"\busing\s+System(\.\w+)*;"#, 5),
            Rule(#"\bnamespace\s+[\w.]+"#, 3),
            Rule(#"Console\.Write"#, 5),
            Rule(#"\bpublic\s+(async\s+)?(class|void|Task)\b"#, 2)
        ]),
        ("Go", [
            Rule(#"^\s*package\s+\w+\s*$"#, 5),
            Rule(#"\bfunc\s+(\(\w+\s+\*?\w+\)\s+)?\w+\("#, 4),
            Rule(#":="#, 3),
            Rule(#"\bfmt\.\w+"#, 5),
            Rule(#"\berr\s*!=\s*nil\b"#, 5)
        ]),
        ("Rust", [
            Rule(#"\bfn\s+\w+\s*[(<]"#, 4),
            Rule(#"\blet\s+mut\b"#, 5),
            Rule(#"^\s*impl\b"#, 3),
            Rule(#"\b(println|vec|format|panic)!\("#, 4),
            Rule(#"&mut\b|&self\b"#, 4),
            Rule(#"^\s*(pub|mod|use)\s+\w+"#, 2)
        ]),
        ("Ruby", [
            Rule(#"^\s*def\s+\w+[?!]?\s*(\(.*\))?\s*$"#, 3),
            Rule(#"^\s*end\s*$"#, 3),
            Rule(#"\bputs\s"#, 3),
            Rule(#"\bdo\s*\|\w+(,\s*\w+)*\|"#, 5),
            Rule(#"^\s*require\s+['"]"#, 3)
        ]),
        ("PHP", [
            Rule(#"<\?php"#, 10),
            Rule(#"\$\w+\s*=[^=]"#, 2),
            Rule(#"\$this->"#, 5)
        ]),
        ("Shell", [
            Rule(#"^#!\s*/(usr/)?bin/(env\s+)?(ba|z|fi)?sh"#, 10),
            Rule(#"^\s*\$?\s*(sudo|echo|export|cd|ls|grep|curl|wget|brew|git|npm|npx|yarn|pnpm|pip3?|docker|kubectl|chmod|chown|mkdir|rm|mv|cp|cat|ssh|scp|tar|make|swift|xcodebuild|python3?|node|cargo|defaults|launchctl|open)\s"#, 3),
            Rule(#"\|\s*(grep|awk|sed|sort|uniq|head|tail|xargs|wc|jq)\b"#, 4),
            Rule(#"^\s*\$?\s*\.{0,2}/[\w.\-/]+\.(sh|py|rb|pl)?(\s|$)"#, 3),
            Rule(#"\s(&&|\|\|)\s"#, 1),
            Rule(#"\s--?[a-zA-Z][\w-]*"#, 1),
            Rule(#"^\s*(fi|done|esac)\s*$"#, 3)
        ]),
        ("SQL", [
            Rule(#"\bSELECT\b[\s\S]+?\bFROM\b"#, 5, caseInsensitive: true),
            Rule(#"\bINSERT\s+INTO\b"#, 5, caseInsensitive: true),
            Rule(#"\bUPDATE\s+\w+\s+SET\b"#, 5, caseInsensitive: true),
            Rule(#"\bDELETE\s+FROM\b"#, 5, caseInsensitive: true),
            Rule(#"\bCREATE\s+(TABLE|INDEX|VIEW|DATABASE)\b"#, 5, caseInsensitive: true),
            Rule(#"\b(WHERE|JOIN|GROUP BY|ORDER BY)\b"#, 1)
        ]),
        ("CSS", [
            Rule(#"^\s*[.#]?[\w-]+([\s,>+~]+[.#]?[\w-:]+)*\s*\{\s*$"#, 2),
            Rule(#"^\s*[\w-]+\s*:\s*[^;{}]+;\s*$"#, 2),
            Rule(#"@(media|import|keyframes)\b"#, 4),
            Rule(#"\b\d+(px|rem|em|vh|vw)\b"#, 2)
        ])
    ]

    /// Returns the detected language name, or nil when the text doesn't look like code.
    static func detect(_ raw: String) -> String? {
        let text = String(raw.prefix(20_000))
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return nil }

        // Structured formats first.
        if let first = trimmed.first, first == "{" || first == "[",
           let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil,
           trimmed.contains(":") || trimmed.contains(",") {
            return "JSON"
        }
        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">"), trimmed.contains("</") || trimmed.contains("/>") {
            let lower = trimmed.lowercased()
            if lower.hasPrefix("<?xml") { return "XML" }
            let htmlTags = ["<html", "<div", "<span", "<p>", "<p ", "<a ", "<body", "<head", "<!doctype", "<ul", "<li", "<table", "<img", "<script", "<style", "<section", "<button", "<input", "<h1", "<h2"]
            return htmlTags.contains(where: lower.contains) ? "HTML" : "XML"
        }

        let lines = trimmed.components(separatedBy: .newlines)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let n = max(nonEmpty.count, 1)

        if n >= 3, isYAML(nonEmpty) { return "YAML" }

        // Generic code signals.
        var generic = 0
        let codeEndings = nonEmpty.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let last = t.last else { return false }
            return ";{}()[],".contains(last) || t.hasSuffix("=>") || t.hasSuffix("->")
        }.count
        if n >= 2, Double(codeEndings) / Double(n) >= 0.4 { generic += 3 }
        let symbols = trimmed.reduce(0) { $0 + ("{}[]()<>;=_$#&|*\\".contains($1) ? 1 : 0) }
        let symbolRatio = Double(symbols) / Double(max(trimmed.count, 1))
        if symbolRatio >= 0.05 { generic += 2 }
        if symbolRatio >= 0.10 { generic += 1 }
        let indented = nonEmpty.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
        if n >= 3, Double(indented) / Double(n) >= 0.3 { generic += 1 }

        // Prose guard: sentences with little punctuation are text, not code.
        let sentenceEnds = trimmed.components(separatedBy: ". ").count - 1
        let looksLikeProse = symbolRatio < 0.02 && sentenceEnds >= 2

        var best: (name: String, score: Int) = ("Code", 0)
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        for (name, rules) in languages {
            var score = 0
            for rule in rules {
                let count = rule.regex.numberOfMatches(in: text, range: range)
                score += rule.weight * min(count, 3)
            }
            if score > best.score { best = (name, score) }
        }

        if looksLikeProse && best.score < 8 { return nil }
        if n == 1 {
            return best.score >= 4 ? best.name : nil
        }
        if best.score >= 5 || (best.score >= 2 && generic >= 3) { return best.score >= 2 ? best.name : "Code" }
        if generic >= 5 { return best.score >= 2 ? best.name : "Code" }
        return nil
    }

    private static func isYAML(_ lines: [String]) -> Bool {
        let regex = try! NSRegularExpression(pattern: #"^\s*(- )?[\w.\-"']+:(\s+\S.*)?$|^\s*- \S"#)
        var matches = 0
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") { matches += 1; continue }
            if t.hasSuffix(".") { return false }
            if regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil { matches += 1 }
        }
        let hasNesting = lines.contains { $0.hasPrefix("  ") }
        return Double(matches) / Double(lines.count) >= 0.85 && hasNesting
    }
}

// MARK: - Highlighting

enum CodeHighlighter {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }

    static let keywordColor = dynamic(0x9B2393, 0xFC5FA3)
    static let stringColor = dynamic(0xC41A16, 0xFC6A5D)
    static let numberColor = dynamic(0x1C00CF, 0xD0BF69)
    static let commentColor = dynamic(0x5D6C79, 0x7F8C98)
    static let typeColor = dynamic(0x3900A0, 0xD0A8FF)
    static let functionColor = dynamic(0x326D74, 0x67B7A4)

    static func highlight(_ text: String, language: String?, fontSize: CGFloat = 12.5) -> NSAttributedString {
        let lang = CodeLanguage.named(language)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        let out = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: para
        ])
        let s = text as NSString
        let len = s.length
        guard len > 0, len < 300_000 else { return out }

        func color(_ range: NSRange, _ c: NSColor) { out.addAttribute(.foregroundColor, value: c, range: range) }
        func has(_ prefix: String, at i: Int) -> Bool {
            let p = prefix as NSString
            return i + p.length <= len && s.substring(with: NSRange(location: i, length: p.length)) == prefix
        }
        func isIdentStart(_ c: unichar) -> Bool {
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 64 || c == 36
        }
        func isIdent(_ c: unichar) -> Bool { isIdentStart(c) || (c >= 48 && c <= 57) }
        func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }

        let quoteUnits = Set(lang.quotes.compactMap { $0.utf16.first })
        let caseInsensitive = lang.name == "SQL"
        var i = 0
        var prevNonSpace: unichar = 0
        while i < len {
            let c = s.character(at: i)

            if let (open, close) = lang.blockComment, has(open, at: i) {
                let searchStart = i + (open as NSString).length
                let r = s.range(of: close, range: NSRange(location: searchStart, length: len - searchStart))
                let end = r.location == NSNotFound ? len : r.location + r.length
                color(NSRange(location: i, length: end - i), commentColor)
                i = end
                continue
            }
            if let lc = lang.lineComments.first(where: { has($0, at: i) }),
               !(lc == "#" && lang.name == "Shell" && i > 0 && isIdent(s.character(at: i - 1))) {
                let lineRange = s.lineRange(for: NSRange(location: i, length: 0))
                let end = lineRange.location + lineRange.length
                color(NSRange(location: i, length: end - i), commentColor)
                i = end
                continue
            }
            if quoteUnits.contains(c) {
                var j = i + 1
                while j < len {
                    let d = s.character(at: j)
                    if d == 92 { j += 2; continue } // backslash escape
                    if d == c { j += 1; break }
                    if d == 10 && c != 96 { break } // strings end at newline (except template literals)
                    j += 1
                }
                let end = min(j, len)
                let range = NSRange(location: i, length: end - i)
                // JSON keys get the "type" color for readability.
                var k = end
                while k < len, s.character(at: k) == 32 { k += 1 }
                if lang.name == "JSON" || lang.name == "YAML", k < len, s.character(at: k) == 58 {
                    color(range, typeColor)
                } else {
                    color(range, stringColor)
                }
                i = end
                prevNonSpace = c
                continue
            }
            if isDigit(c), i == 0 || !isIdent(s.character(at: i - 1)) {
                var j = i + 1
                while j < len {
                    let d = s.character(at: j)
                    if isIdent(d) || d == 46 { j += 1 } else { break }
                }
                color(NSRange(location: i, length: j - i), numberColor)
                i = j
                continue
            }
            if isIdentStart(c) {
                var j = i + 1
                while j < len, isIdent(s.character(at: j)) || (lang.isMarkup && (s.character(at: j) == 45 || s.character(at: j) == 58)) { j += 1 }
                let range = NSRange(location: i, length: j - i)
                let word = s.substring(with: range)
                var k = j
                while k < len, s.character(at: k) == 32 { k += 1 }
                let next: unichar = k < len ? s.character(at: k) : 0

                if lang.isMarkup {
                    if prevNonSpace == 60 || prevNonSpace == 47 && i >= 2 && s.character(at: i - 2) == 60 { color(range, keywordColor) }
                    else if next == 61 { color(range, typeColor) }
                } else if lang.keywords.contains(caseInsensitive ? word.lowercased() : word) || word.hasPrefix("@") {
                    color(range, keywordColor)
                } else if next == 40 { // (
                    color(range, functionColor)
                } else if let first = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first), word.count > 1 {
                    color(range, typeColor)
                }
                i = j
                prevNonSpace = s.character(at: j - 1)
                continue
            }
            if c != 32 && c != 9 && c != 10 { prevNonSpace = c }
            i += 1
        }
        return out
    }
}
