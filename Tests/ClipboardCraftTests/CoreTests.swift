import Foundation
import Testing
@testable import ClipboardCraft

// MARK: - Helpers

private func snapshot(_ reps: [(String, Data)]) -> PasteboardSnapshot {
    PasteboardSnapshot(items: [reps.map { (type: $0.0, data: $0.1) }], fileURLs: [])
}

private func textSnapshot(_ s: String, extra: [(String, Data)] = []) -> PasteboardSnapshot {
    snapshot([(PBType.plainText, Data(s.utf8))] + extra)
}

private let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

// MARK: - Colors

@Suite struct ColorParserTests {
    @Test func hexForms() {
        #expect(ColorParser.parse("#FF6B6B")?.hex == "#FF6B6B")
        #expect(ColorParser.parse("#abc")?.hex == "#AABBCC")
        #expect(ColorParser.parse("  #00ff0080 ")?.hex == "#00FF0080")
        #expect(ColorParser.parse("0x336699")?.hex == "#336699")
    }

    @Test func functionalForms() {
        #expect(ColorParser.parse("rgb(255, 0, 0)")?.hex == "#FF0000")
        #expect(ColorParser.parse("rgba(0,0,255,0.5)")?.hex == "#0000FF80")
        #expect(ColorParser.parse("hsl(120, 100%, 50%)")?.hex == "#00FF00")
        #expect(ColorParser.parse("rgb(255 128 0)")?.hex == "#FF8000")
    }

    @Test func rejectsNonColors() {
        #expect(ColorParser.parse("facade") == nil)
        #expect(ColorParser.parse("#GGG") == nil)
        #expect(ColorParser.parse("#12345") == nil)
        #expect(ColorParser.parse("rgb(300, 0, 0)") == nil)
        #expect(ColorParser.parse("the color #fff is white") == nil)
    }

    @Test func conversions() throws {
        let c = try #require(ColorParser.parse("#FF0000"))
        #expect(c.rgbString == "rgb(255, 0, 0)")
        #expect(c.hslString == "hsl(0, 100%, 50%)")
        #expect(!c.isLight)
        #expect(ColorParser.parse("#FFFFFF")?.isLight == true)
    }
}

// MARK: - Code

@Suite struct CodeDetectorTests {
    @Test func detectsLanguages() {
        #expect(CodeDetector.detect("func greet(name: String) -> String {\n    let message = \"Hi \\(name)\"\n    return message\n}") == "Swift")
        #expect(CodeDetector.detect("def add(a, b):\n    return a + b\n\nprint(add(1, 2))") == "Python")
        #expect(CodeDetector.detect("{\n  \"name\": \"x\",\n  \"version\": 1\n}") == "JSON")
        #expect(CodeDetector.detect("const total = items.map(x => x.price);\nconsole.log(total);") == "JavaScript")
        #expect(CodeDetector.detect("SELECT id, name FROM users WHERE age > 30;") == "SQL")
        #expect(CodeDetector.detect("git commit -m 'Initial commit' --amend") == "Shell")
        #expect(CodeDetector.detect("./build.sh --install && open -a \"Clipboard Craft\"") == "Shell")
        #expect(CodeDetector.detect("<div class=\"card\"><p>Hello</p></div>") == "HTML")
        #expect(CodeDetector.detect("package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"hi\")\n}") == "Go")
    }

    @Test func ignoresProse() {
        #expect(CodeDetector.detect("Hello there, how are you doing today?") == nil)
        #expect(CodeDetector.detect("Note: buy milk.") == nil)
        #expect(CodeDetector.detect("We met yesterday. The plan is solid. Let's ship it next week.") == nil)
        #expect(CodeDetector.detect("سلام دنیا! این یک متن فارسی است.") == nil)
        #expect(CodeDetector.detect("make sure to call me") == nil)
    }

    @Test func highlighterKeepsText() {
        let src = "let x = 42 // answer\nprint(\"hi\")"
        let out = CodeHighlighter.highlight(src, language: "Swift")
        #expect(out.string == src)
    }
}

// MARK: - Search

@Suite struct SearchTests {
    @Test func persianNormalisation() {
        #expect(SearchFold.fold("كتاب") == SearchFold.fold("کتاب"))      // Arabic kaf → Persian kaf
        #expect(SearchFold.fold("علي") == SearchFold.fold("علی"))        // Arabic yeh → Persian yeh
        #expect(SearchFold.fold("می‌خواهم") == SearchFold.fold("میخواهم")) // ZWNJ ignored
        #expect(SearchFold.fold("۱۲۳") == "123")                          // Persian digits
    }

    @Test func latinFolding() {
        #expect(SearchFold.fold("Café RÉSUMÉ") == "cafe resume")
    }

    @Test func queryTokens() {
        let q = SearchQuery("type:image is:pinned app:Safari in:work hello World")
        #expect(q.kinds == [.image])
        #expect(q.pinned)
        #expect(q.app == "safari")
        #expect(q.collection == "work")
        #expect(q.terms == ["hello", "world"])
        #expect(SearchQuery("type:links").kinds == [.link])
        #expect(SearchQuery("").isEmpty)
    }
}

// MARK: - Classification

@Suite struct ClassifierTests {
    @Test func links() throws {
        let c = try #require(ContentClassifier.classify(textSnapshot("https://www.apple.com/macos/\n")))
        #expect(c.kind == .link)
        #expect(c.meta.urlHost == "www.apple.com")
        #expect(ContentClassifier.classify(textSnapshot("www.example.com"))?.kind == .link)
        #expect(ContentClassifier.classify(textSnapshot("see https://apple.com for more"))?.kind == .text)
    }

    @Test func colorsAndCode() {
        #expect(ContentClassifier.classify(textSnapshot("#FF6B6B"))?.kind == .color)
        let code = ContentClassifier.classify(textSnapshot("def f(x):\n    return x * 2\n"))
        #expect(code?.kind == .code)
        #expect(code?.meta.codeLanguage == "Python")
    }

    @Test func plainAndRichText() {
        let plain = ContentClassifier.classify(textSnapshot("Hello world\nSecond line\n"))
        #expect(plain?.kind == .text)
        #expect(plain?.meta.lineCount == 2)
        #expect(plain?.title == "Hello world")

        let rtf = Data(#"{\rtf1\ansi {\b Bold} text}"#.utf8)
        let rich = ContentClassifier.classify(textSnapshot("Bold text", extra: [(PBType.rtf, rtf)]))
        #expect(rich?.kind == .richText)
        #expect(rich?.meta.richType == "rtf")

        // RTF-only content still yields searchable text.
        let rtfOnly = ContentClassifier.classify(snapshot([(PBType.rtf, rtf)]))
        #expect(rtfOnly?.kind == .richText)
        #expect(rtfOnly?.text?.contains("Bold") == true)
    }

    @Test func images() throws {
        let c = try #require(ContentClassifier.classify(snapshot([(PBType.png, tinyPNG)])))
        #expect(c.kind == .image)
        #expect(c.meta.imageWidth == 1 && c.meta.imageHeight == 1)
        // Browsers put the image URL next to the image: still an image.
        let web = ContentClassifier.classify(snapshot([(PBType.png, tinyPNG), (PBType.plainText, Data("https://x.com/a.png".utf8))]))
        #expect(web?.kind == .image)
        // Spreadsheet cells ship a rendered image too, but they're text.
        let cells = ContentClassifier.classify(snapshot([(PBType.png, tinyPNG), (PBType.plainText, Data("A1\tB1".utf8))]))
        #expect(cells?.kind == .text)
    }

    @Test func files() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
        try Data("hello".utf8).write(to: a)
        try Data("world!".utf8).write(to: b)
        let c = ContentClassifier.classifyFiles([a, b])
        #expect(c.kind == .file)
        #expect(c.meta.files?.count == 2)
        #expect(c.meta.files?.first?.size == 5)
        #expect(c.title == "2 files")
        // Same files → same hash (duplicate detection).
        #expect(ContentClassifier.classifyFiles([a, b]).hash == c.hash)
    }

    @Test func otherData() {
        let c = ContentClassifier.classify(snapshot([("com.example.custom", Data([1, 2, 3]))]))
        #expect(c?.kind == .other)
    }

    @Test func emptyIsIgnored() {
        #expect(ContentClassifier.classify(textSnapshot("   \n ")) == nil || ContentClassifier.classify(textSnapshot("   \n "))?.kind == .other)
    }
}

// MARK: - Shortcuts

@Suite struct ShortcutTests {
    @Test func defaultQuickPanelIsShiftCommandC() {
        let s = Shortcut.defaultQuickPanel
        #expect(s.modifierSymbols == "⇧⌘")
        #expect(s.keyCode == 8) // kVK_ANSI_C
        #expect(Shortcut.functionKeys.contains(Int(s.keyCode)) == false)
    }

    @Test func shortcutListsRoundTrip() throws {
        let list = [Shortcut.defaultQuickPanel, Shortcut(keyCode: 49, modifiers: NSEventModifierOption)]
        let data = try JSONEncoder().encode(list)
        #expect(try JSONDecoder().decode([Shortcut].self, from: data) == list)
    }
}

private let NSEventModifierOption: UInt = 1 << 19 // NSEvent.ModifierFlags.option

// MARK: - Store

@MainActor
@Suite(.serialized) struct StoreTests {
    private func makeStore() throws -> ClipStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cc-test-\(UUID().uuidString).sqlite")
        return ClipStore(db: try Database(url: url))
    }

    private func item(_ text: String, kind: ClipKind = .text, age: TimeInterval = 0, pinned: Bool = false) -> ClipItem {
        let date = Date().addingTimeInterval(-age)
        var i = ClipItem(id: UUID(), kind: kind, createdAt: date, updatedAt: date, copyCount: 1, title: text, text: text,
                         contentHash: "text:" + ContentClassifier.sha(text), sourceBundleID: "com.apple.Safari",
                         sourceAppName: "Safari", isPinned: pinned, isFavorite: false, byteSize: 1000, meta: ClipMeta(),
                         collectionIDs: [])
        i.searchKey = SearchFold.searchKey(for: i)
        return i
    }

    @Test func insertSearchAndPersist() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cc-test-\(UUID().uuidString).sqlite")
        let store = ClipStore(db: try Database(url: url))
        store.insert(item("Quarterly report"))
        store.insert(item("كتاب فارسی"))
        #expect(store.results(query: "report", filter: .all).count == 1)
        #expect(store.results(query: "کتاب", filter: .all).count == 1)
        #expect(store.results(query: "app:safari", filter: .all).count == 2)
        #expect(store.results(query: "type:image", filter: .all).isEmpty)

        let reopened = try Database(url: url).loadClips()
        #expect(reopened.count == 2)
        #expect(reopened.first?.title == "كتاب فارسی")
    }

    @Test func duplicatesMoveToTop() throws {
        let store = try makeStore()
        let first = item("alpha")
        store.insert(first)
        store.insert(item("beta"))
        #expect(store.items.first?.title == "beta")
        let handled = store.handleDuplicate(hash: first.contentHash, behavior: .moveToTop, sourceBundleID: nil, sourceAppName: nil)
        #expect(handled)
        #expect(store.items.first?.id == first.id)
        #expect(store.items.first?.copyCount == 2)
        #expect(!store.handleDuplicate(hash: first.contentHash, behavior: .keepBoth, sourceBundleID: nil, sourceAppName: nil))
    }

    @Test func deleteAndUndo() throws {
        let store = try makeStore()
        let a = item("one"), b = item("two")
        store.insert(a); store.insert(b)
        store.delete([a.id, b.id])
        #expect(store.items.isEmpty)
        #expect(store.toast?.undoIDs?.count == 2)
        store.undoLastDeletion()
        #expect(store.items.count == 2)
        #expect(store.items.first?.id == b.id)
    }

    @Test func pinsCollectionsAndRetention() throws {
        let store = try makeStore()
        let settings = AppSettings.shared
        let saved = (settings.retention, settings.maxItems, settings.maxStorageMB)
        defer { settings.retention = saved.0; settings.maxItems = saved.1; settings.maxStorageMB = saved.2 }
        settings.retention = .week
        settings.maxItems = 0
        settings.maxStorageMB = 0

        let old = item("old", age: 30 * 86_400)
        let oldPinned = item("old pinned", age: 30 * 86_400, pinned: true)
        let oldInCollection = item("old in collection", age: 30 * 86_400)
        let fresh = item("fresh")
        [old, oldPinned, oldInCollection, fresh].forEach(store.insert)
        let c = store.createCollection(name: "Work", symbol: "briefcase.fill", color: .blue)
        store.setCollection(c.id, member: true, for: [oldInCollection.id])

        store.runMaintenance()
        let titles = Set(store.items.map(\.title))
        #expect(titles == ["old pinned", "old in collection", "fresh"])
        #expect(store.results(query: "in:work", filter: .all).map(\.id) == [oldInCollection.id])
    }

    @Test func maxItemsKeepsNewest() throws {
        let store = try makeStore()
        let settings = AppSettings.shared
        let saved = (settings.retention, settings.maxItems, settings.maxStorageMB)
        defer { settings.retention = saved.0; settings.maxItems = saved.1; settings.maxStorageMB = saved.2 }
        settings.retention = .forever
        settings.maxItems = 3
        settings.maxStorageMB = 0
        for n in 0..<5 { store.insert(item("clip \(n)", age: Double(10 - n))) }
        store.runMaintenance()
        #expect(store.items.map(\.title) == ["clip 4", "clip 3", "clip 2"])
    }

    @Test func editingText() throws {
        let store = try makeStore()
        let a = item("first draft")
        store.insert(a)
        store.updateText(a.id, to: "final version\nwith two lines")
        let edited = try #require(store.item(a.id))
        #expect(edited.title == "final version")
        #expect(edited.meta.lineCount == 2)
        #expect(edited.meta.edited == true)
        #expect(store.results(query: "final", filter: .all).count == 1)
        BlobStore.shared.remove(a.id)
    }
}
