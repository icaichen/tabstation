import AppKit

enum DisplayStyle: String, CaseIterable {
    case full = "full"
    case thumbnailsOnly = "thumbnailsOnly"
    case iconsOnly = "iconsOnly"

    var title: String {
        switch self {
        case .full: return "Thumbnails & Titles"
        case .thumbnailsOnly: return "Thumbnails Only"
        case .iconsOnly: return "App Icons Only"
        }
    }

    var showsTitles: Bool {
        switch self {
        case .full: return true
        case .thumbnailsOnly, .iconsOnly: return false
        }
    }

    var showsThumbnails: Bool {
        switch self {
        case .full, .thumbnailsOnly: return true
        case .iconsOnly: return false
        }
    }

    static var current: DisplayStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "TabStation.displayStyle"),
                  let style = DisplayStyle(rawValue: raw) else {
                return .thumbnailsOnly
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "TabStation.displayStyle")
            NotificationCenter.default.post(name: .tabStationAppearanceChanged, object: nil)
        }
    }
}

enum ThumbnailSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var baseHeight: CGFloat {
        switch self {
        case .small: return 110
        case .medium: return 155
        case .large: return 215
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .small: return 230
        case .medium: return 310
        case .large: return 430
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .small: return 72
        case .medium: return 94
        case .large: return 132
        }
    }

    var iconDimension: CGFloat {
        switch self {
        case .small: return 56
        case .medium: return 72
        case .large: return 92
        }
    }

    static var current: ThumbnailSize {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "TabStation.thumbnailSize"),
                  let size = ThumbnailSize(rawValue: raw) else {
                return .medium
            }
            return size
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "TabStation.thumbnailSize")
            NotificationCenter.default.post(name: .tabStationAppearanceChanged, object: nil)
        }
    }
}

enum AppearanceTheme: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum BackgroundStyle: String, CaseIterable {
    case frosted
    case clear
    case tinted

    var title: String {
        switch self {
        case .frosted: return "Liquid Glass"
        case .clear: return "Clear Glass"
        case .tinted: return "Solid"
        }
    }
}

enum AccentColorChoice: String, CaseIterable {
    case system
    case graphite
    case blue
    case purple
    case pink
    case orange
    case green
    case custom

    var title: String {
        switch self {
        case .system: return "System"
        case .graphite: return "Graphite"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .orange: return "Orange"
        case .green: return "Green"
        case .custom: return "Custom"
        }
    }

    static var presets: [AccentColorChoice] {
        [.system, .graphite, .blue, .purple, .pink, .orange, .green]
    }
}

enum AppearancePreferences {
    private enum Keys {
        static let showFooterHints = "TabStation.showFooterHints"
        static let autoAdjustSize = "TabStation.autoAdjustSize"
        static let autoPreviewOnHold = "TabStation.autoPreviewOnHold"
        static let theme = "TabStation.appearanceTheme"
        static let backgroundStyle = "TabStation.backgroundStyle"
        static let panelOpacity = "TabStation.panelOpacity"
        static let accentChoice = "TabStation.accentColorChoice"
        static let customAccentRGB = "TabStation.customAccentColorRGB"
    }

    static var autoPreviewOnHold: Bool {
        get { UserDefaults.standard.object(forKey: Keys.autoPreviewOnHold) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.autoPreviewOnHold)
            postChange()
        }
    }

    static var showFooterHints: Bool {
        get { UserDefaults.standard.object(forKey: Keys.showFooterHints) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.showFooterHints)
            postChange()
        }
    }

    static var autoAdjustSize: Bool {
        get { UserDefaults.standard.object(forKey: Keys.autoAdjustSize) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.autoAdjustSize)
            postChange()
        }
    }

    static var theme: AppearanceTheme {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Keys.theme),
                  let value = AppearanceTheme(rawValue: raw) else {
                return .system
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.theme)
            postChange()
        }
    }

    static var backgroundStyle: BackgroundStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Keys.backgroundStyle),
                  let value = BackgroundStyle(rawValue: raw) else {
                return .frosted
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.backgroundStyle)
            postChange()
        }
    }

    static var panelOpacity: Double {
        get {
            guard UserDefaults.standard.object(forKey: Keys.panelOpacity) != nil else {
                return 0.85
            }
            return min(max(UserDefaults.standard.double(forKey: Keys.panelOpacity), 0.30), 1.0)
        }
        set {
            let clamped = min(max(newValue, 0.30), 1.0)
            UserDefaults.standard.set(clamped, forKey: Keys.panelOpacity)
            postChange()
        }
    }

    static var accentColorChoice: AccentColorChoice {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Keys.accentChoice),
                  let value = AccentColorChoice(rawValue: raw) else {
                return .graphite
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.accentChoice)
            postChange()
        }
    }

    static var customAccentColor: NSColor {
        get {
            guard let comps = UserDefaults.standard.array(forKey: Keys.customAccentRGB) as? [Double],
                  comps.count >= 3 else {
                return NSColor.systemBlue
            }
            return NSColor(
                srgbRed: CGFloat(comps[0]),
                green: CGFloat(comps[1]),
                blue: CGFloat(comps[2]),
                alpha: 1.0
            )
        }
        set {
            let converted = newValue.usingColorSpace(.sRGB) ?? newValue
            let comps = [
                Double(converted.redComponent),
                Double(converted.greenComponent),
                Double(converted.blueComponent)
            ]
            UserDefaults.standard.set(comps, forKey: Keys.customAccentRGB)
            UserDefaults.standard.set(AccentColorChoice.custom.rawValue, forKey: Keys.accentChoice)
            postChange()
        }
    }

    static func resetDefaults() {
        let keys = [
            Keys.showFooterHints,
            Keys.autoAdjustSize,
            Keys.autoPreviewOnHold,
            Keys.theme,
            Keys.backgroundStyle,
            Keys.panelOpacity,
            Keys.accentChoice,
            Keys.customAccentRGB
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        postChange()
    }

    private static func postChange() {
        NotificationCenter.default.post(name: .tabStationAppearanceChanged, object: nil)
    }
}

extension Notification.Name {
    static let tabStationAppearanceChanged = Notification.Name("TabStation.appearanceChanged")
}

/// User-configurable feature toggles exposed in the Preferences "Features" tab.
enum FeaturePreferences {
    private enum Keys {
        static let arrowKeySnapping = "TabStation.arrowKeySnapping"
        static let spaceQuickLook = "TabStation.spaceQuickLook"
        static let hoverActionPills = "TabStation.hoverActionPills"
        static let pinShortcut = "TabStation.pinShortcut"
        static let displayMoveShortcut = "TabStation.displayMoveShortcut"
        static let browserTabsShortcut = "TabStation.browserTabsShortcut"
        static let includeBrowserTabs = "TabStation.includeBrowserTabs"
    }

    static var arrowKeySnappingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.arrowKeySnapping) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.arrowKeySnapping)
            postChange()
        }
    }

    static var spaceQuickLookEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.spaceQuickLook) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.spaceQuickLook)
            postChange()
        }
    }

    static var hoverActionPillsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.hoverActionPills) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.hoverActionPills)
            postChange()
        }
    }

    static var pinShortcutEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.pinShortcut) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.pinShortcut)
            postChange()
        }
    }

    static var displayMoveShortcutEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.displayMoveShortcut) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.displayMoveShortcut)
            postChange()
        }
    }

    static var browserTabsShortcutEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.browserTabsShortcut) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.browserTabsShortcut)
            postChange()
        }
    }

    static var includeBrowserTabsByDefault: Bool {
        get { UserDefaults.standard.object(forKey: Keys.includeBrowserTabs) as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.includeBrowserTabs)
            postChange()
        }
    }

    static func resetDefaults() {
        for key in [
            Keys.arrowKeySnapping,
            Keys.spaceQuickLook,
            Keys.hoverActionPills,
            Keys.pinShortcut,
            Keys.displayMoveShortcut,
            Keys.browserTabsShortcut,
            Keys.includeBrowserTabs
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        postChange()
    }

    private static func postChange() {
        NotificationCenter.default.post(name: .tabStationAppearanceChanged, object: nil)
    }
}

/// General workspace behavior defaults.
enum GeneralPreferences {
    private enum Keys {
        static let followActiveDisplay = "TabStation.followActiveDisplay"
    }

    static var followActiveDisplay: Bool {
        get { UserDefaults.standard.object(forKey: Keys.followActiveDisplay) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.followActiveDisplay) }
    }

    static func resetDefaults() {
        UserDefaults.standard.removeObject(forKey: Keys.followActiveDisplay)
    }
}
