import AppKit
import Carbon.HIToolbox
import Observation

// MARK: - Shortcut

struct Shortcut: Codable, Hashable {
    var keyCode: UInt32
    /// Device-independent `NSEvent.ModifierFlags` raw value.
    var modifiers: UInt

    static let defaultQuickPanel = Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue)
    static let defaultMainWindow = Shortcut(keyCode: UInt32(kVK_Space), modifiers: NSEvent.ModifierFlags([.option, .shift]).rawValue)

    init(keyCode: UInt32, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // A global shortcut needs at least one of ⌘ ⌥ ⌃ (function keys are allowed alone).
        let isFunctionKey = Self.functionKeys.contains(Int(event.keyCode))
        guard isFunctionKey || !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        self.keyCode = UInt32(event.keyCode)
        self.modifiers = flags.rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        let f = modifierFlags
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var modifierSymbols: String {
        let f = modifierFlags
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s
    }

    var keySymbol: String { Self.keyName(for: Int(keyCode)) }

    var displayString: String { modifierSymbols + keySymbol }

    /// Individual glyphs, for rendering as key caps.
    var keyCaps: [String] { modifierSymbols.map(String.init) + [keySymbol] }

    static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ]

    static func keyName(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_ANSI_KeypadEnter: return "⌅"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default:
            return KeyboardLayout.character(for: UInt16(keyCode))?.uppercased() ?? "#\(keyCode)"
        }
    }
}

// MARK: - Keyboard layout helpers

enum KeyboardLayout {
    /// Character produced by a key code in the current ASCII-capable layout (so ⌘-shortcuts
    /// display Latin letters even when a Persian/Arabic layout is active).
    static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }

    /// Key code that types `character` in the current ASCII-capable layout (e.g. "v" on Dvorak).
    static func keyCode(for char: String) -> UInt16? {
        for code in UInt16(0)..<128 {
            if character(for: code)?.lowercased() == char.lowercased() { return code }
        }
        return nil
    }
}

// MARK: - Hot key center

@MainActor
@Observable
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// Shortcuts macOS refused to register (usually already taken by another app).
    private(set) var failed: Set<Shortcut> = []

    @ObservationIgnored private var refs: [UInt32: EventHotKeyRef] = [:]
    @ObservationIgnored private var groups: [UInt32: (shortcuts: [Shortcut], handler: () -> Void)] = [:]
    @ObservationIgnored private var eventHandler: EventHandlerRef?
    @ObservationIgnored private var suspended = false

    /// Each action owns a block of hot key IDs: `action * 100 + index`.
    private static let stride: UInt32 = 100

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    func register(id: UInt32, shortcuts: [Shortcut], handler: @escaping () -> Void) {
        unregister(id: id)
        var unique: [Shortcut] = []
        for s in shortcuts where !unique.contains(s) { unique.append(s) }
        groups[id] = (unique, handler)
        if !suspended { install(group: id) }
    }

    func unregister(id: UInt32) {
        removeRefs(group: id)
        if let old = groups.removeValue(forKey: id) { failed.subtract(old.shortcuts) }
    }

    /// Temporarily disables all hot keys (used while recording a new shortcut).
    func suspend() {
        suspended = true
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    func resume() {
        suspended = false
        for id in groups.keys { install(group: id) }
    }

    private func install(group id: UInt32) {
        guard let group = groups[id] else { return }
        removeRefs(group: id)
        for (i, shortcut) in group.shortcuts.enumerated() {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x43435246), id: id * Self.stride + UInt32(i)) // 'CCRF'
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hkID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs[hkID.id] = ref
                failed.remove(shortcut)
            } else {
                failed.insert(shortcut)
                NSLog("ClipboardCraft: failed to register hot key \(shortcut.displayString) (\(status))")
            }
        }
    }

    private func removeRefs(group id: UInt32) {
        for key in refs.keys where key / Self.stride == id {
            if let ref = refs.removeValue(forKey: key) { UnregisterEventHotKey(ref) }
        }
    }

    private func fire(_ hotKeyID: UInt32) {
        groups[hotKeyID / Self.stride]?.handler()
    }
}
