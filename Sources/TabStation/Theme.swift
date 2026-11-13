import AppKit

/// Visual constants and adaptive palette for the switcher HUD.
enum Theme {
    static let panelCornerRadius: CGFloat = 20
    static let cellCornerRadius: CGFloat = 10
    static let cardCornerRadius: CGFloat = 13
    static let iconTileCornerRadius: CGFloat = 15
    static let panelBorderWidth: CGFloat = 0.5

    /// Accent color driven by AppearancePreferences (or nil when Graphite/neutral glass is chosen).
    static var accent: NSColor {
        switch AppearancePreferences.accentColorChoice {
        case .system:
            return NSColor.controlAccentColor
        case .graphite:
            return NSColor(name: nil) { appearance in
                isDark(appearance)
                    ? NSColor.white.withAlphaComponent(0.90)
                    : NSColor.black.withAlphaComponent(0.85)
            }
        case .blue:
            return NSColor.systemBlue
        case .purple:
            return NSColor.systemPurple
        case .pink:
            return NSColor.systemPink
        case .orange:
            return NSColor.systemOrange
        case .green:
            return NSColor.systemGreen
        case .custom:
            return AppearancePreferences.customAccentColor
        }
    }

    static var isNeutralHighlight: Bool {
        AppearancePreferences.accentColorChoice == .graphite
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Hairline specular edge around the outer HUD container.
    static var panelBorder: NSColor {
        NSColor(name: nil) { appearance in
            isDark(appearance)
                ? NSColor.white.withAlphaComponent(0.10)
                : NSColor.black.withAlphaComponent(0.08)
        }
    }

    /// Solid / tinted backing color behind or instead of the visual effect blur.
    static func panelBackingColor(for appearance: NSAppearance) -> NSColor {
        let opacity = CGFloat(AppearancePreferences.panelOpacity)
        let dark = isDark(appearance)
        switch AppearancePreferences.backgroundStyle {
        case .frosted:
            // Keep pure macOS HUD vibrancy at default opacity; only deepen when pushed near 100%.
            let extra = max(0, (opacity - 0.88) / 0.12)
            guard extra > 0.01 else { return .clear }
            return dark
                ? NSColor(calibratedWhite: 0.11, alpha: extra * 0.55)
                : NSColor(calibratedWhite: 0.98, alpha: extra * 0.55)
        case .clear:
            return dark
                ? NSColor(calibratedWhite: 0.08, alpha: opacity * 0.28)
                : NSColor(calibratedWhite: 0.98, alpha: opacity * 0.30)
        case .tinted:
            return dark
                ? NSColor(calibratedWhite: 0.12, alpha: opacity)
                : NSColor(calibratedWhite: 0.97, alpha: opacity)
        }
    }

    /// Subtle backing for a thumbnail card surface (adaptive to Light/Dark).
    static var cardBackground: NSColor {
        NSColor(name: nil) { appearance in
            isDark(appearance)
                ? NSColor.white.withAlphaComponent(0.05)
                : NSColor.black.withAlphaComponent(0.04)
        }
    }

    /// Hairline border around an unselected thumbnail card.
    static var cellBorder: NSColor {
        NSColor(name: nil) { appearance in
            isDark(appearance)
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.09)
        }
    }

    /// Subtle translucent plate behind the selected item (Apple Cmd+Tab / AltTab style).
    static var selectionFill: NSColor {
        let base = accent
        return NSColor(name: nil) { appearance in
            let dark = isDark(appearance)
            if isNeutralHighlight {
                return dark
                    ? NSColor.white.withAlphaComponent(0.14)
                    : NSColor.black.withAlphaComponent(0.08)
            }
            return base.withAlphaComponent(dark ? 0.22 : 0.15)
        }
    }

    /// Crisp hairline ring around the selected item (borderless for Apple Graphite look).
    static var selectionBorder: NSColor {
        let base = accent
        return NSColor(name: nil) { appearance in
            let dark = isDark(appearance)
            if isNeutralHighlight {
                return .clear
            }
            return base.withAlphaComponent(dark ? 0.78 : 0.72)
        }
    }

    /// Soft icon-well backing for minimized/windowless fallback tiles.
    static var fallbackTileBackground: NSColor {
        NSColor(name: nil) { appearance in
            isDark(appearance)
                ? NSColor.white.withAlphaComponent(0.07)
                : NSColor.black.withAlphaComponent(0.05)
        }
    }

    /// Small app-icon corner badge backing inside a thumbnail card.
    static var badgeBackground: NSColor {
        NSColor(name: nil) { appearance in
            isDark(appearance)
                ? NSColor(calibratedWhite: 0.14, alpha: 0.88)
                : NSColor(calibratedWhite: 0.98, alpha: 0.92)
        }
    }

    static var badgeBorder: NSColor {
        NSColor(name: nil) { appearance in
            isDark(appearance)
                ? NSColor.white.withAlphaComponent(0.22)
                : NSColor.black.withAlphaComponent(0.12)
        }
    }

    /// Hover quick-action pill colors.
    static var hoverPillBackground: NSColor {
        NSColor(name: nil) { appearance in
            isDark(appearance)
                ? NSColor(calibratedWhite: 0.10, alpha: 0.88)
                : NSColor(calibratedWhite: 0.99, alpha: 0.94)
        }
    }

    static var hoverPillBorder: NSColor {
        NSColor(name: nil) { appearance in
            isDark(appearance)
                ? NSColor.white.withAlphaComponent(0.20)
                : NSColor.black.withAlphaComponent(0.12)
        }
    }

    static var hoverPillText: NSColor {
        NSColor.labelColor
    }

    static var hoverPillDivider: NSColor {
        NSColor.separatorColor
    }

    static var captionText: NSColor {
        NSColor.secondaryLabelColor
    }

    static var selectedCaptionText: NSColor {
        NSColor.labelColor
    }

    static var secondaryCaptionText: NSColor {
        NSColor.secondaryLabelColor
    }

    static var footerText: NSColor {
        NSColor.tertiaryLabelColor
    }

    /// Clearance around each tile so the selection ring is never clipped.
    static let cellShadowHeadroom: CGFloat = 4

    static let idleItemAlpha: CGFloat = 0.90
    static let filteredOutItemAlpha: CGFloat = 0.20
    static let selectedItemAlpha: CGFloat = 1.0

    static let selectedScale: CGFloat = 1.02
    static let selectedShadow = NSShadow()
}

extension Theme {
    static func configure() {
        selectedShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        selectedShadow.shadowBlurRadius = 14
        selectedShadow.shadowOffset = NSSize(width: 0, height: -3)
    }
}

/// Animation timing constants.
enum Motion {
    static let selection: TimeInterval = 0.12
    static let show: TimeInterval = 0.14
    static let hide: TimeInterval = 0.09
}
