import AppKit

/// Virtual keycodes we care about by name.
enum KeyCode {
    static let q: UInt16 = 12
    static let w: UInt16 = 13
    static let d: UInt16 = 2
    static let p: UInt16 = 35
    static let c: UInt16 = 8
    static let b: UInt16 = 11
    static let s: UInt16 = 1
    static let m: UInt16 = 46
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let grave: UInt16 = 50
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126

    /// Bare modifier keys can't be a shortcut on their own — pressing and
    /// releasing ⌥ to record it would be indistinguishable from finishing.
    static let modifierKeys: Set<UInt16> = [
        54, 55, 56, 57, 58, 59, 60, 61, 62, // ⇧ ⇪ ⌃ ⌥
    ]

    /// Carbon/HIToolbox keycodes are keyed to *physical key positions*, not to
    /// alphabetical order — Q is 12 while I is 34, and the digits occupy the
    /// gaps between letters. So the display map has to be spelled out; deriving
    /// it from a numeric range renders Q as "M".
    static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    private static let names: [UInt16: String] = [
        // Letters
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G",
        6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "U",
        31: "O", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
        45: "N", 46: "M",
        // Digits
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
        22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        // Punctuation
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'",
        41: ";", 42: "\\", 43: ",", 44: "/", 47: ".",
        50: "`",
        // Editing / navigation
        returnKey: "\u{21A9}",
        tab: "Tab",
        space: "Space",
        51: "\u{232B}",
        escape: "esc",
        115: "\u{2196}", 116: "\u{21DE}", 119: "\u{2198}", 121: "\u{21DF}",
        123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
        // Function keys
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
        97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12",
    ]
}

/// A modifier + key combination. This is everything a key event gives us, and
/// it's the unit the switcher gesture is built from: hold `modifiers`, tap
/// `keyCode`, release `modifiers` to commit.
struct Shortcut: Equatable {
    var modifiers: NSEvent.ModifierFlags
    var keyCode: UInt16

    static let optionTab = Shortcut(modifiers: [.option], keyCode: KeyCode.tab)

    /// The subset we persist and compare — function/flags bits are noise.
    var normalized: NSEvent.ModifierFlags {
        modifiers.intersection([.command, .option, .control, .shift])
    }

    static func glyphs(for modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "\u{2303}" }   // ⌃
        if modifiers.contains(.option) { s += "\u{2325}" }    // ⌥
        if modifiers.contains(.shift) { s += "\u{21E7}" }     // ⇧
        if modifiers.contains(.command) { s += "\u{2318}" }   // ⌘
        return s
    }

    var displayString: String {
        Shortcut.glyphs(for: normalized) + KeyCode.name(for: keyCode)
    }

    /// The two secondary keys ride on the same held modifier, so their labels
    /// have to follow whatever modifier the user picked.
    func display(_ key: UInt16, suffix: String) -> String {
        Shortcut.glyphs(for: normalized) + KeyCode.name(for: key) + " " + suffix
    }
}

/// The core gestures: primary switcher and same-app switcher.
enum ShortcutRole: String, CaseIterable {
    case primary = "primary"
    case sameApp = "sameApp"

    var title: String {
        switch self {
        case .primary: return L10n.t("Shortcut 1", "快捷键 1")
        case .sameApp: return L10n.t("Shortcut 2", "快捷键 2")
        }
    }

    var subtitle: String {
        switch self {
        case .primary: return L10n.t("Cycle through windows of open apps.", "在已打开应用的窗口间切换。")
        case .sameApp: return L10n.t("Cycle only between windows of the frontmost app.", "仅在当前最前应用的窗口间切换。")
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .primary: return .optionTab
        case .sameApp: return Shortcut(modifiers: [.option], keyCode: KeyCode.grave)
        }
    }

    /// Storage key. The original single-shortcut build used "TabStation.shortcut"
    /// for the primary — keep reading it so existing users don't lose theirs.
    var legacyKey: String? {
        self == .primary ? "TabStation.shortcut" : nil
    }

    var storeKey: String { "TabStation.shortcut.\(rawValue)" }
}

enum WindowScope: String, CaseIterable {
    case allApps = "allApps"
    case activeApp = "activeApp"

    var title: String {
        switch self {
        case .allApps: return L10n.t("All apps", "全部应用")
        case .activeApp: return L10n.t("Active app", "仅当前应用")
        }
    }
}

enum ShortcutScopeStore {
    static func load(_ role: ShortcutRole) -> WindowScope {
        if let val = UserDefaults.standard.string(forKey: "TabStation.scope.\(role.rawValue)"),
           let scope = WindowScope(rawValue: val) {
            return scope
        }
        return role == .sameApp ? .activeApp : .allApps
    }

    static func save(_ scope: WindowScope, for role: ShortcutRole) {
        UserDefaults.standard.set(scope.rawValue, forKey: "TabStation.scope.\(role.rawValue)")
    }
}

/// Rejects shortcuts that would shadow a system binding or collide with another
/// switcher action.
enum ShortcutValidator {
    static func validate(_ shortcut: Shortcut, for role: ShortcutRole) -> String? {
        let modifiers = shortcut.normalized

        if modifiers.isEmpty {
            return L10n.t("Add at least one modifier — ⌃, ⌥, ⇧ or ⌘.", "请至少添加一个修饰键 — ⌃、⌥、⇧ 或 ⌘。")
        }
        if KeyCode.modifierKeys.contains(shortcut.keyCode) {
            let name = KeyCode.name(for: shortcut.keyCode)
            return L10n.t("\(name) on its own can't be a shortcut.", "不能单独使用 \(name) 作为快捷键。")
        }
        if shortcut.keyCode == KeyCode.escape {
            return L10n.t("esc is reserved for cancelling.", "esc 键已保留用于取消切换。")
        }
        if modifiers == [.command] && [0, 6, 7, 8, 9].contains(shortcut.keyCode) {
            return L10n.t(
                "⌘Z, ⌘C, ⌘V, ⌘X, ⌘A are standard editing shortcuts — pick a different key.",
                "⌘Z、⌘C、⌘V、⌘X、⌘A 为系统编辑快捷键，请换用其他按键。"
            )
        }
        return nil
    }

    /// A soft, non-blocking note for shortcuts macOS already uses. Recording one
    /// is allowed — the event tap swallows it while TabStation runs — but the
    /// user should know they're displacing a system behaviour.
    static func warning(for shortcut: Shortcut) -> String? {
        if UserDefaults.standard.bool(forKey: "TabStation.overrideCommandTab") {
            return nil
        }
        let modifiers = shortcut.normalized
        guard modifiers.contains(.command) else { return nil }

        if modifiers == [.command] && shortcut.keyCode == KeyCode.space {
            return L10n.t(
                "⌘Space opens Spotlight. AltDeck will take it over while it's running.",
                "⌘Space 默认用于打开聚焦搜索，AltDeck 运行时将临时接管该快捷键。"
            )
        }
        return nil
    }
}

/// Persists the user's choices in UserDefaults.
enum ShortcutStore {
    static func load(_ role: ShortcutRole = .primary) -> Shortcut {
        if let data = UserDefaults.standard.data(forKey: role.storeKey),
           let parts = try? JSONDecoder().decode([UInt64].self, from: data),
           parts.count == 2 {
            return Shortcut(
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(parts[0])),
                keyCode: UInt16(truncatingIfNeeded: parts[1])
            )
        }
        // Migrate the original single-shortcut build.
        if let legacy = role.legacyKey,
           let data = UserDefaults.standard.data(forKey: legacy),
           let parts = try? JSONDecoder().decode([UInt64].self, from: data),
           parts.count == 2 {
            let migrated = Shortcut(
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(parts[0])),
                keyCode: UInt16(truncatingIfNeeded: parts[1])
            )
            save(migrated, for: role)
            return migrated
        }
        return role.defaultShortcut
    }

    /// Backwards-compatible alias for the primary shortcut.
    static func load() -> Shortcut { load(.primary) }

    static func save(_ shortcut: Shortcut, for role: ShortcutRole = .primary) {
        let payload: [UInt64] = [UInt64(shortcut.normalized.rawValue), UInt64(shortcut.keyCode)]
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: role.storeKey)
        // Keep the legacy key in sync for the primary, in case anything still reads it.
        if let legacy = role.legacyKey {
            UserDefaults.standard.set(data, forKey: legacy)
        }
    }

    /// Backwards-compatible alias.
    static func save(_ shortcut: Shortcut) { save(shortcut, for: .primary) }

    static func loadAll() -> [ShortcutRole: Shortcut] {
        Dictionary(uniqueKeysWithValues: ShortcutRole.allCases.map { ($0, load($0)) })
    }

    static func reset(_ role: ShortcutRole? = nil) {
        if let role {
            UserDefaults.standard.removeObject(forKey: role.storeKey)
            if let legacy = role.legacyKey {
                UserDefaults.standard.removeObject(forKey: legacy)
            }
        } else {
            for role in ShortcutRole.allCases {
                UserDefaults.standard.removeObject(forKey: role.storeKey)
                if let legacy = role.legacyKey {
                    UserDefaults.standard.removeObject(forKey: legacy)
                }
            }
        }
    }

    /// Backwards-compatible alias (resets everything, like the old Reset button).
    static func reset() { reset(nil) }
}