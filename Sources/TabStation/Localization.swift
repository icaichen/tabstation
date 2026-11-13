import Foundation

/// User-selectable interface language for AltDeck, persisted in UserDefaults.
enum AppLanguage: String, CaseIterable {
    case system = "system"
    case en = "en"
    case zhHans = "zh-Hans"

    private static let storeKey = "TabStation.appLanguage"

    static var current: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storeKey),
                  let lang = AppLanguage(rawValue: raw) else {
                return .system
            }
            return lang
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storeKey)
            NotificationCenter.default.post(name: .tabStationAppearanceChanged, object: nil)
        }
    }

    /// Resolves `.system` against the user's macOS preferred language list.
    static var resolved: AppLanguage {
        let lang = current
        guard lang == .system else { return lang }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("zh") ? .zhHans : .en
    }

    var title: String {
        switch self {
        case .system: return L10n.t("System", "跟随系统")
        case .en: return "English"
        case .zhHans: return "简体中文"
        }
    }
}

/// Lightweight bilingual helper supporting live switching without bundle restarts.
enum L10n {
    static var isChinese: Bool {
        AppLanguage.resolved == .zhHans
    }

    static func t(_ en: String, _ zh: String) -> String {
        isChinese ? zh : en
    }
}
