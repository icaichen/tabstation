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

    /// Resolves effective appearance honoring explicit Light/Dark override immediately,
    /// even before an offscreen panel completes an AppKit display pass.
    static func resolvedAppearance(for view: NSView? = nil) -> NSAppearance {
        if let override = AppearancePreferences.theme.nsAppearance {
            return override
        }
        return view?.effectiveAppearance ?? NSApp.effectiveAppearance
    }

    /// Hairline specular edge around the outer HUD container.
    static var panelBorder: NSColor {
        NSColor(name: nil) { appearance in
            isDark(appearance)
                ? NSColor.white.withAlphaComponent(0.16)
                : NSColor.black.withAlphaComponent(0.10)
        }
    }

    /// Solid / tinted backing color behind or instead of glass/vibrancy.
    static func panelBackingColor(for appearance: NSAppearance) -> NSColor {
        let opacity = CGFloat(AppearancePreferences.panelOpacity)
        let dark = isDark(appearance)
        switch AppearancePreferences.backgroundStyle {
        case .frosted:
            let tintStrength = max(0, (opacity - 0.55) / 0.45)
            guard tintStrength > 0.01 else { return .clear }
            return dark
                ? NSColor(calibratedWhite: 0.08, alpha: tintStrength * 0.36)
                : NSColor(calibratedWhite: 0.98, alpha: tintStrength * 0.32)
        case .clear:
            let tintStrength = max(0, (opacity - 0.65) / 0.35)
            guard tintStrength > 0.01 else { return .clear }
            return dark
                ? NSColor(calibratedWhite: 0.06, alpha: tintStrength * 0.16)
                : NSColor(calibratedWhite: 1.0, alpha: tintStrength * 0.14)
        case .tinted:
            // Keep Solid mode crisply matte across the slider instead of muddy semi-gray.
            let t = min(max((opacity - 0.30) / 0.70, 0), 1)
            let solidAlpha = 0.78 + t * 0.22
            return dark
                ? NSColor(calibratedWhite: 0.125, alpha: solidAlpha)
                : NSColor(calibratedWhite: 0.965, alpha: solidAlpha)
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

extension NSColor {
    func resolvedCGColor(for appearance: NSAppearance) -> CGColor {
        var resolved: CGColor = cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = self.cgColor
        }
        return resolved
    }
}

/// Shared adaptive backdrop surface supporting true macOS 26+ Liquid Glass (`NSGlassEffectView`),
/// Clear Glass, Solid matte studio surface, and pre-macOS 26 vibrancy fallback.
final class GlassSurfaceView: NSView {
    let contentContainer = NSView()

    private let solidBackdrop = NSView()
    private let legacyBlurView = NSVisualEffectView()
    private var glassEffectView: NSView?
    private let cornerRadiusValue: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadiusValue = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        contentContainer.autoresizingMask = [.width, .height]
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.borderWidth = 0

        solidBackdrop.wantsLayer = true
        solidBackdrop.layer?.cornerRadius = cornerRadius
        solidBackdrop.layer?.cornerCurve = .continuous
        solidBackdrop.layer?.masksToBounds = true
        solidBackdrop.layer?.borderWidth = Theme.panelBorderWidth
        addSubview(solidBackdrop)

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: .zero)
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.contentView = contentContainer
            addSubview(glass)
            glassEffectView = glass
        } else {
            legacyBlurView.material = .popover
            legacyBlurView.blendingMode = .behindWindow
            legacyBlurView.state = .active
            addSubview(legacyBlurView)
            addSubview(contentContainer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        solidBackdrop.frame = bounds
        if let glassEffectView {
            glassEffectView.frame = bounds
        } else {
            legacyBlurView.frame = bounds
        }
        if contentContainer.superview === self {
            contentContainer.frame = bounds
        }
    }

    func applyAppearance() {
        let appearance = Theme.resolvedAppearance(for: self)
        self.appearance = appearance
        let style = AppearancePreferences.backgroundStyle
        let opacity = CGFloat(AppearancePreferences.panelOpacity)
        let dark = Theme.isDark(appearance)

        solidBackdrop.layer?.borderColor = Theme.panelBorder.resolvedCGColor(for: appearance)

        if #available(macOS 26.0, *), let glass = glassEffectView as? NSGlassEffectView {
            switch style {
            case .frosted:
                glass.isHidden = false
                glass.style = .regular
                glass.alphaValue = 1.0
                let baseWhite: CGFloat = dark ? 0.10 : 0.99
                let tintAlpha = 0.08 + ((opacity - 0.30) / 0.70) * 0.34
                glass.tintColor = NSColor(calibratedWhite: baseWhite, alpha: tintAlpha)
                if glass.contentView !== contentContainer {
                    glass.contentView = contentContainer
                }
                solidBackdrop.isHidden = true
            case .clear:
                glass.isHidden = false
                glass.style = .clear
                glass.alphaValue = 1.0
                let baseWhite: CGFloat = dark ? 0.08 : 1.0
                let tintAlpha = max(0.0, ((opacity - 0.30) / 0.70) * 0.16)
                glass.tintColor = tintAlpha > 0.01 ? NSColor(calibratedWhite: baseWhite, alpha: tintAlpha) : nil
                if glass.contentView !== contentContainer {
                    glass.contentView = contentContainer
                }
                solidBackdrop.isHidden = true
            case .tinted:
                // Ensure contentContainer remains visible above solidBackdrop when glass is hidden.
                if contentContainer.superview !== self {
                    glass.contentView = nil
                    addSubview(contentContainer)
                }
                glass.isHidden = true
                solidBackdrop.isHidden = false
                solidBackdrop.layer?.backgroundColor = Theme.panelBackingColor(for: appearance).resolvedCGColor(for: appearance)
                contentContainer.frame = bounds
            }
            return
        }

        // Fallback for macOS 14–15
        switch style {
        case .frosted:
            legacyBlurView.isHidden = false
            legacyBlurView.material = .popover
            legacyBlurView.alphaValue = max(0.45, opacity)
            solidBackdrop.isHidden = true
        case .clear:
            legacyBlurView.isHidden = false
            legacyBlurView.material = .hudWindow
            legacyBlurView.alphaValue = max(0.12, opacity * 0.35)
            solidBackdrop.isHidden = true
        case .tinted:
            legacyBlurView.isHidden = true
            solidBackdrop.isHidden = false
            solidBackdrop.layer?.backgroundColor = Theme.panelBackingColor(for: appearance).resolvedCGColor(for: appearance)
        }
    }
}
