#if DEBUG
import AppKit
import SwiftUI

/// Debug-only "showcase" mode used to produce the README screenshots.
///
///     CC_DATA_DIR=/tmp/demo CC_SHOWCASE=/tmp/scenes.txt ClipboardCraft
///
/// Seeds a demo library, puts a generated backdrop behind the app's windows and walks through a
/// series of scenes. For each scene it appends `name x y w h` (screen points, top-left origin) to
/// the scenes file so an external `screencapture -R` loop can grab exactly that region.
@MainActor
enum Showcase {
    static var scenesFile: String? { ProcessInfo.processInfo.environment["CC_SHOWCASE"] }
    static var isActive: Bool { scenesFile != nil }

    private static var backdrop: NSWindow?
    private static var ids: [String: UUID] = [:]

    static func run(_ services: AppServices) {
        guard let file = scenesFile else { return }
        FileManager.default.createFile(atPath: file, contents: nil)
        services.library.showOnboarding = false
        NSApp.appearance = NSAppearance(named: .aqua)
        seed(services)

        var t: TimeInterval = 4.5 // let the capture pipeline finish seeding
        func at(_ delay: TimeInterval, _ action: @escaping () -> Void) {
            t += delay
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: action)
        }
        func scene(_ name: String, settle: TimeInterval = 2.4, margin: CGFloat = 44, _ setup: @escaping () -> NSWindow?) {
            var window: NSWindow?
            at(0.6) { window = setup() }
            at(settle) { if let window { record(name, window.frame.insetBy(dx: -margin, dy: -margin), file) } }
            at(1.6) {}
        }

        at(0) { finishSeeding(services); showBackdrop(dark: false) }

        scene("quick-panel", margin: 56) { quickPanel(services, select: "code") }
        scene("quick-panel-image", margin: 56) { quickPanel(services, select: "image") }
        scene("library") { library(services, mode: .list, select: "image") }
        scene("library-grid") { library(services, mode: .grid, select: "code") }
        scene("settings-shortcuts") { settings(services, .shortcuts) }
        scene("settings-storage") { settings(services, .storage) }

        at(0.5) {
            services.windows.mainWindow?.orderOut(nil)
            NSApp.windows.first { $0.title == "Settings" }?.orderOut(nil)
            NSApp.appearance = NSAppearance(named: .darkAqua)
            showBackdrop(dark: true)
        }
        scene("quick-panel-dark", margin: 56) { quickPanel(services, select: "files") }
        scene("library-dark") { library(services, mode: .list, select: "checklist") }

        at(0.5) {
            services.library.viewMode = .list
            try? "done\n".appendLine(to: file)
            exit(0)
        }
    }

    // MARK: Scenes

    private static var stage: NSRect {
        let screen = NSScreen.screens[0]
        return screen.visibleFrame
    }

    private static func centered(_ size: NSSize, lift: CGFloat = 20) -> NSRect {
        let s = stage
        return NSRect(x: (s.midX - size.width / 2).rounded(), y: (s.midY - size.height / 2 + lift).rounded(),
                      width: size.width, height: size.height)
    }

    private static func quickPanel(_ services: AppServices, select key: String) -> NSWindow? {
        hideWindows(services)
        let qp = services.quickPanel
        if !qp.isVisible { qp.show() }
        qp.model.selectedID = ids[key]
        // Once the open animation ends, pin the panel onto the backdrop screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            qp.debugWindow?.setFrame(centered(QuickPanelController.fullSize, lift: 40), display: true)
        }
        return qp.debugWindow
    }

    private static func library(_ services: AppServices, mode: LibraryViewMode, select key: String) -> NSWindow? {
        services.quickPanel.hide(animated: false)
        NSApp.windows.first { $0.title == "Settings" }?.orderOut(nil)
        services.library.sidebar = .all
        services.library.searchText = ""
        services.library.viewMode = mode
        services.windows.showMain(select: ids[key])
        guard let w = services.windows.mainWindow else { return nil }
        w.setFrameAutosaveName("")
        w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        w.setFrame(centered(NSSize(width: 1240, height: 760)), display: true)
        return w
    }

    private static func settings(_ services: AppServices, _ pane: SettingsPane) -> NSWindow? {
        services.quickPanel.hide(animated: false)
        services.windows.mainWindow?.orderOut(nil)
        services.windows.showSettings(pane: pane)
        guard let w = NSApp.windows.first(where: { $0.title == "Settings" || $0.title == pane.title }) else { return nil }
        w.setFrameAutosaveName("")
        w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        w.setFrame(centered(NSSize(width: 820, height: 600)), display: true)
        return w
    }

    private static func hideWindows(_ services: AppServices) {
        services.windows.mainWindow?.orderOut(nil)
        NSApp.windows.first { $0.title == "Settings" }?.orderOut(nil)
    }

    private static func record(_ name: String, _ rect: NSRect, _ file: String) {
        let screenHeight = NSScreen.screens[0].frame.height
        let r = rect.intersection(stage)
        let line = "\(name) \(Int(r.minX)) \(Int(screenHeight - r.maxY)) \(Int(r.width)) \(Int(r.height))"
        try? line.appendLine(to: file)
    }

    // MARK: Backdrop

    private static func showBackdrop(dark: Bool) {
        let frame = NSScreen.screens[0].frame
        let w = backdrop ?? {
            let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .floating
            w.isReleasedWhenClosed = false
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary]
            backdrop = w
            return w
        }()
        let view = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        view.imageScaling = .scaleAxesIndependently
        view.image = Artwork.image(size: CGSize(width: 1600, height: 1000), palette: dark ? .night : .day)
        w.contentView = view
        w.setFrame(frame, display: true)
        w.orderFrontRegardless()
    }

    // MARK: Demo data

    private static func seed(_ services: AppServices) {
        guard services.store.items.isEmpty else { return }
        let dir = AppPaths.dataFolder.appendingPathComponent("DemoFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pdf = dir.appendingPathComponent("Q4 Roadmap.pdf")
        let png = dir.appendingPathComponent("Hero Artwork.png")
        Artwork.writeRoadmapPDF(to: pdf)
        if let tiff = Artwork.image(size: CGSize(width: 600, height: 400), palette: .sunset).tiffRepresentation,
           let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? data.write(to: png)
        }
        let artwork = Artwork.image(size: CGSize(width: 800, height: 500), palette: .aurora)
        let artworkPNG = artwork.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) } ?? Data()

        let rtf: Data = {
            let s = NSMutableAttributedString()
            let title = NSFont.systemFont(ofSize: 18, weight: .bold)
            let body = NSFont.systemFont(ofSize: 13)
            s.append(NSAttributedString(string: "Launch checklist\n", attributes: [.font: title]))
            for (done, line) in [(true, "Final QA pass on macOS 27"), (true, "Record the product video"), (false, "Write release notes"), (false, "Ship v1.0 🚀")] {
                s.append(NSAttributedString(string: (done ? "☑︎ " : "☐ ") + line + "\n", attributes: [
                    .font: body, .foregroundColor: done ? NSColor.secondaryLabelColor : NSColor.labelColor,
                    .strikethroughStyle: done ? NSUnderlineStyle.single.rawValue : 0
                ]))
            }
            return (try? s.data(from: NSRange(location: 0, length: s.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
        }()

        let swift = """
        struct ClipCard: View {
            let clip: Clip
            @State private var isHovered = false

            var body: some View {
                Label(clip.title, systemImage: clip.kind.symbol)
                    .padding(12)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                    .scaleEffect(isHovered ? 1.03 : 1)
                    .onHover { isHovered = $0 }
            }
        }
        """
        let json = """
        {
          "name": "clipboard-craft",
          "version": "1.0.0",
          "platforms": ["macOS 26", "macOS 27"],
          "features": ["history", "files", "images", "glass"]
        }
        """

        func text(_ s: String) -> [(String, Data)] { [(PBType.plainText, Data(s.utf8))] }
        let entries: [(key: String, app: String, bundle: String, reps: [(String, Data)], files: [URL])] = [
            ("mail", "Mail", "com.apple.mail", text("Thanks for the update! I’ll send the final assets by Friday.\n\nBest,\nSara"), []),
            ("repo", "Safari", "com.apple.Safari", text("https://github.com/MHMK2002/clipboard-craft"), []),
            ("json", "Terminal", "com.apple.Terminal", text(json), []),
            ("files", "Finder", "com.apple.finder", [], [pdf, png]),
            ("color", "Digital Color Meter", "com.apple.DigitalColorMeter", text("#5E5CE6"), []),
            ("checklist", "Notes", "com.apple.Notes", text(NSAttributedString(rtf: rtf, documentAttributes: nil)?.string ?? "") + [(PBType.rtf, rtf)], []),
            ("persian", "Messages", "com.apple.MobileSMS", text("جلسه‌ی طراحی فردا ساعت ۱۰ صبح است — لطفاً نسخه‌ی جدید را قبلش بررسی کن 🙏"), []),
            ("shell", "Terminal", "com.apple.Terminal", text("./build.sh --install && open -a \"Clipboard Craft\""), []),
            ("hig", "Safari", "com.apple.Safari", text("https://developer.apple.com/design/human-interface-guidelines/materials"), []),
            ("image", "Preview", "com.apple.Preview", [(PBType.png, artworkPNG)], []),
            ("code", "Safari", "com.apple.Safari", text(swift), [])
        ]
        let options = CaptureProcessor.Options(duplicateBehavior: .keepBoth, saveFileCopies: true, maxFileCopyBytes: 50_000_000)
        for e in entries {
            var snap = PasteboardSnapshot(items: e.reps.isEmpty ? [] : [e.reps.map { (type: $0.0, data: $0.1) }], fileURLs: e.files)
            snap.sourceAppName = e.app
            snap.sourceBundleID = e.bundle
            CaptureProcessor.shared.process(snap, options: options, store: services.store)
        }
        demoOrder = entries.map(\.key)
    }

    private static var demoOrder: [String] = []

    /// Spreads the demo clips over time and organises them once the capture queue has stored them.
    private static func finishSeeding(_ services: AppServices) {
        let store = services.store
        guard demoOrder.count == store.items.count else {
            // Reusing an existing demo library: map keys by title.
            for item in store.items { ids[item.title] = item.id }
            return
        }
        // Items were inserted oldest-first, so store.items is newest-first.
        for (key, item) in zip(demoOrder.reversed(), store.items) { ids[key] = item.id }
        let minutesAgo: [String: Double] = [
            "code": 2, "image": 9, "hig": 24, "shell": 41, "persian": 63, "checklist": 180,
            "color": 60 * 26, "files": 60 * 30, "json": 60 * 24 * 3, "repo": 60 * 24 * 8, "mail": 60 * 24 * 9
        ]
        for (key, minutes) in minutesAgo {
            if let id = ids[key] { store.debugSetDate(id, Date().addingTimeInterval(-minutes * 60)) }
        }
        if let id = ids["hig"] { store.setLinkTitle(id, "Materials | Apple Developer Documentation") }
        if let id = ids["repo"] { store.setLinkTitle(id, "MHMK2002/clipboard-craft · GitHub") }
        store.setPinned([ids["checklist"], ids["color"]].compactMap { $0 }, true)
        store.setFavorite([ids["code"], ids["image"]].compactMap { $0 }, true)
        let collections = Dictionary(store.collections.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
        if let c = collections["Code"] { store.setCollection(c, member: true, for: [ids["code"], ids["json"], ids["shell"]].compactMap { $0 }) }
        if let c = collections["Work"] { store.setCollection(c, member: true, for: [ids["files"], ids["checklist"], ids["mail"]].compactMap { $0 }) }
        if let c = collections["Research"] { store.setCollection(c, member: true, for: [ids["hig"]].compactMap { $0 }) }
        if let c = collections["Personal"] { store.setCollection(c, member: true, for: [ids["persian"]].compactMap { $0 }) }
        store.toast = nil
    }
}

// MARK: - Generated artwork

enum Artwork {
    enum Palette { case day, night, aurora, sunset }

    static func image(size: CGSize, palette: Palette) -> NSImage {
        let (base, blobs): ([NSColor], [(CGPoint, CGFloat, NSColor)]) = {
            func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
            switch palette {
            case .day:
                return ([c(196, 214, 255), c(222, 205, 255), c(255, 214, 230)],
                        [(CGPoint(x: 0.2, y: 0.75), 0.55, c(120, 170, 255)), (CGPoint(x: 0.85, y: 0.25), 0.5, c(255, 160, 200)),
                         (CGPoint(x: 0.6, y: 0.85), 0.35, c(180, 140, 255)), (CGPoint(x: 0.1, y: 0.1), 0.4, c(140, 230, 230))])
            case .night:
                return ([c(18, 20, 48), c(42, 24, 78), c(70, 22, 70)],
                        [(CGPoint(x: 0.2, y: 0.75), 0.55, c(60, 90, 220)), (CGPoint(x: 0.85, y: 0.25), 0.5, c(190, 60, 150)),
                         (CGPoint(x: 0.6, y: 0.9), 0.35, c(110, 70, 230)), (CGPoint(x: 0.1, y: 0.1), 0.4, c(30, 150, 170))])
            case .aurora:
                return ([c(10, 30, 60), c(20, 70, 110), c(40, 20, 90)],
                        [(CGPoint(x: 0.3, y: 0.6), 0.5, c(40, 220, 170)), (CGPoint(x: 0.7, y: 0.7), 0.45, c(80, 140, 255)),
                         (CGPoint(x: 0.8, y: 0.2), 0.4, c(200, 80, 220)), (CGPoint(x: 0.15, y: 0.2), 0.35, c(30, 180, 220))])
            case .sunset:
                return ([c(255, 140, 90), c(240, 90, 120), c(110, 60, 160)],
                        [(CGPoint(x: 0.25, y: 0.3), 0.45, c(255, 210, 120)), (CGPoint(x: 0.8, y: 0.75), 0.45, c(255, 110, 160)),
                         (CGPoint(x: 0.55, y: 0.1), 0.4, c(140, 80, 220))])
            }
        }()
        let img = NSImage(size: size)
        img.lockFocus()
        let rect = CGRect(origin: .zero, size: size)
        NSGradient(colors: base)?.draw(in: rect, angle: -35)
        for (p, r, color) in blobs {
            let center = CGPoint(x: p.x * size.width, y: p.y * size.height)
            let radius = r * max(size.width, size.height)
            NSGradient(colors: [color.withAlphaComponent(0.85), color.withAlphaComponent(0)])?
                .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
        }
        if palette == .aurora || palette == .sunset {
            // A soft horizon line of "hills" so it reads as a picture.
            let hills = NSBezierPath()
            hills.move(to: CGPoint(x: 0, y: 0))
            hills.line(to: CGPoint(x: 0, y: size.height * 0.28))
            hills.curve(to: CGPoint(x: size.width * 0.45, y: size.height * 0.24),
                        controlPoint1: CGPoint(x: size.width * 0.15, y: size.height * 0.42),
                        controlPoint2: CGPoint(x: size.width * 0.3, y: size.height * 0.18))
            hills.curve(to: CGPoint(x: size.width, y: size.height * 0.32),
                        controlPoint1: CGPoint(x: size.width * 0.65, y: size.height * 0.32),
                        controlPoint2: CGPoint(x: size.width * 0.85, y: size.height * 0.42))
            hills.line(to: CGPoint(x: size.width, y: 0))
            hills.close()
            NSColor.black.withAlphaComponent(palette == .aurora ? 0.45 : 0.3).setFill()
            hills.fill()
        }
        img.unlockFocus()
        return img
    }

    static func writeRoadmapPDF(to url: URL) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSColor(srgbRed: 0.36, green: 0.36, blue: 0.9, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 662, width: 612, height: 130)).fill()
        NSAttributedString(string: "Q4 Roadmap", attributes: [.font: NSFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: NSColor.white])
            .draw(at: CGPoint(x: 48, y: 700))
        var y: CGFloat = 600
        for (i, line) in ["Smart history & search", "Real files and images", "Quick panel with Liquid Glass", "Collections & pins", "Storage clean-up"].enumerated() {
            NSAttributedString(string: "\(i + 1).  \(line)", attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor.black])
                .draw(at: CGPoint(x: 56, y: y))
            NSColor(white: 0.85, alpha: 1).setFill()
            NSBezierPath(roundedRect: CGRect(x: 56, y: y - 22, width: CGFloat(260 + i * 40), height: 8), xRadius: 4, yRadius: 4).fill()
            y -= 80
        }
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
    }
}

private extension String {
    func appendLine(to path: String) throws {
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((self.hasSuffix("\n") ? self : self + "\n").utf8))
    }
}
#endif
