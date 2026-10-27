#if DEBUG
import AppKit
import SwiftUI

/// Debug aid: `CC_SNAPSHOT_DIR=/tmp/shots ClipboardCraft` renders the main UI surfaces to PNGs.
@MainActor
enum DebugSnapshots {
    static var sidebarWindow: NSWindow?
    static func runIfRequested(_ services: AppServices) {
        if ProcessInfo.processInfo.environment["CC_SELFTEST"] != nil { selfTest(services); return }
        guard let dir = ProcessInfo.processInfo.environment["CC_SNAPSHOT_DIR"] else { return }
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let dark = ProcessInfo.processInfo.environment["CC_SNAPSHOT_DARK"] != nil
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let suffix = dark ? "-dark" : ""

        var steps: [(TimeInterval, () -> Void)] = []
        steps.append((1.0, { services.library.showOnboarding = false; services.quickPanel.show() }))
        steps.append((1.5, { snap(services.quickPanel.debugWindow, out.appendingPathComponent("quick\(suffix).png")) }))
        steps.append((0.3, {
            services.quickPanel.model.moveSelection(1)
        }))
        steps.append((0.8, { snap(services.quickPanel.debugWindow, out.appendingPathComponent("quick2\(suffix).png")) }))
        steps.append((0.3, {
            services.quickPanel.hide(animated: false)
            services.windows.showMain(select: services.store.items.first?.id)
        }))
        steps.append((2.0, { snap(services.windows.mainWindow, out.appendingPathComponent("main\(suffix).png")) }))
        steps.append((0.3, { services.library.viewMode = .grid }))
        steps.append((1.5, { snap(services.windows.mainWindow, out.appendingPathComponent("grid\(suffix).png")) }))
        steps.append((0.3, { services.library.viewMode = .list }))
        for pane in SettingsPane.allCases where pane != .about {
            steps.append((0.4, { services.windows.showSettings(pane: pane) }))
            steps.append((1.2, { snap(NSApp.windows.first { $0.title == "Settings" || $0.title == pane.title && $0 !== services.windows.mainWindow }, out.appendingPathComponent("settings-\(pane.rawValue)\(suffix).png")) }))
        }
        steps.append((0.5, {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = NSHostingView(rootView: SidebarView(library: services.library, store: services.store).frame(width: 260, height: 700))
            w.orderFront(nil)
            sidebarWindow = w
        }))
        steps.append((1.2, { snap(sidebarWindow, out.appendingPathComponent("sidebar\(suffix).png")) }))
        steps.append((0.5, { NSApp.terminate(nil) }))

        var delay: TimeInterval = 0
        for (d, action) in steps {
            delay += d
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
        }
    }

    /// Copies every stored clip back to the pasteboard and reports what other apps would receive.
    static func selfTest(_ services: AppServices) {
        setvbuf(stdout, nil, _IONBF, 0)
        services.library.showOnboarding = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let pb = NSPasteboard.general
            for item in services.store.items {
                services.paste.copy([item])
                let types = pb.types?.map(\.rawValue).filter { !$0.hasPrefix("dyn.") } ?? []
                var detail = ""
                switch item.kind {
                case .file:
                    let urls = (pb.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
                    detail = urls.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }.joined(separator: ", ")
                case .image:
                    let tiff = pb.data(forType: .tiff)?.count ?? 0
                    let png = pb.data(forType: .png)?.count ?? 0
                    detail = "png=\(png)B tiff(lazy)=\(tiff)B"
                case .richText:
                    detail = "rtf=\(pb.data(forType: .rtf)?.count ?? 0)B string=\(pb.string(forType: .string)?.prefix(30) ?? "nil")"
                default:
                    detail = "string=\(pb.string(forType: .string)?.prefix(40) ?? "nil")"
                }
                print("SELFTEST \(item.kind.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(item.displayTitle.prefix(28)) | types=\(types) | \(detail)")
            }
            if let text = services.store.items.first(where: { $0.kind == .text }) {
                services.paste.copy([text], plainText: true)
                print("SELFTEST plain-text copy → \(pb.types?.map(\.rawValue) ?? [])")
            }
            print("SELFTEST recorded own writes? count=\(services.store.items.count)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                print("SELFTEST after 1s count=\(services.store.items.count) (should be unchanged)")
                exit(0)
            }
        }
    }

    static func snap(_ window: NSWindow?, _ url: URL) {
        guard let window, let view = window.contentView?.superview ?? window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
