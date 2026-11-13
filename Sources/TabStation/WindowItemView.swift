import AppKit

private extension NSColor {
    func resolvedCGColor(for appearance: NSAppearance) -> CGColor {
        var resolved: CGColor = cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = self.cgColor
        }
        return resolved
    }
}

// MARK: - Action Pill Button

/// A tactile macOS-style micro-action button with smooth rounded hover highlight.
final class ActionPillButton: NSButton {

    var isDestructive = false
    private var isHovered = false {
        didSet { updateVisuals() }
    }
    private var tracking: NSTrackingArea?

    init(symbol: String, tip: String, isDestructive: Bool = false) {
        super.init(frame: .zero)
        self.isDestructive = isDestructive
        self.toolTip = tip
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        let config = NSImage.SymbolConfiguration(pointSize: isDestructive ? 9.5 : 10.5, weight: .semibold)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(config)
        updateVisuals()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisuals()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    private func updateVisuals() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let labelColor = Theme.hoverPillText
        if isHovered {
            if isDestructive {
                layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.20).resolvedCGColor(for: effectiveAppearance)
                contentTintColor = .systemRed
            } else {
                layer?.backgroundColor = labelColor.withAlphaComponent(0.12).resolvedCGColor(for: effectiveAppearance)
                contentTintColor = labelColor
            }
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            contentTintColor = isDestructive
                ? labelColor.withAlphaComponent(0.60)
                : labelColor.withAlphaComponent(0.82)
        }
        CATransaction.commit()
    }
}

// MARK: - Action Pill Divider

/// Subtle 0.5pt vertical divider line separating logical button groups.
final class PillDivider: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 0.25
        updateColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func updateColor() {
        layer?.backgroundColor = Theme.hoverPillDivider.resolvedCGColor(for: effectiveAppearance)
    }
}

// MARK: - Action Pill Bar

/// Lightweight GPU-friendly translucent capsule holding window tiling and close actions.
final class ActionPillBar: NSView {

    private let surface = NSView()
    let leftSplitButton = ActionPillButton(symbol: "rectangle.lefthalf.filled", tip: "Snap Left (←)")
    let rightSplitButton = ActionPillButton(symbol: "rectangle.righthalf.filled", tip: "Snap Right (→)")
    private let divider1 = PillDivider()
    let snapPopoverButton = ActionPillButton(symbol: "square.grid.2x2", tip: "Screen Grid (All Layouts)")
    private let divider2 = PillDivider()
    let closeButton = ActionPillButton(symbol: "xmark", tip: "Close Window (W)", isDestructive: true)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        surface.wantsLayer = true
        surface.layer?.cornerCurve = .continuous
        surface.layer?.borderWidth = 0.5
        surface.layer?.masksToBounds = true
        addSubview(surface)

        addSubview(leftSplitButton)
        addSubview(rightSplitButton)
        addSubview(divider1)
        addSubview(snapPopoverButton)
        addSubview(divider2)
        addSubview(closeButton)
        updateSurfaceColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurfaceColors()
    }

    private func updateSurfaceColors() {
        surface.layer?.backgroundColor = Theme.hoverPillBackground.resolvedCGColor(for: effectiveAppearance)
        surface.layer?.borderColor = Theme.hoverPillBorder.resolvedCGColor(for: effectiveAppearance)
    }

    override func layout() {
        super.layout()
        surface.frame = bounds
        surface.layer?.cornerRadius = (bounds.height / 2).rounded(.down)

        let h = bounds.height
        let btnH: CGFloat = h - 6
        let btnY: CGFloat = 3
        let divH: CGFloat = max(8, h * 0.44)
        let divY: CGFloat = (h - divH) / 2

        let pad: CGFloat = 3
        let divW: CGFloat = 0.5
        let gap: CGFloat = 1.5

        let fixedWidth = pad * 2 + divW * 2 + gap * 3
        let avail = bounds.width - fixedWidth
        let btnW = max(12, (avail / 4).rounded())

        var curX = pad
        leftSplitButton.frame = NSRect(x: curX, y: btnY, width: btnW, height: btnH)
        curX += btnW + gap

        rightSplitButton.frame = NSRect(x: curX, y: btnY, width: btnW, height: btnH)
        curX += btnW + gap

        divider1.frame = NSRect(x: curX, y: divY, width: divW, height: divH)
        curX += divW + gap

        snapPopoverButton.frame = NSRect(x: curX, y: btnY, width: btnW, height: btnH)
        curX += btnW + gap

        divider2.frame = NSRect(x: curX, y: divY, width: divW, height: divH)
        curX += divW + gap

        let lastW = bounds.width - pad - curX
        closeButton.frame = NSRect(x: curX, y: btnY, width: max(btnW, lastW), height: btnH)
    }
}

// MARK: - Window Item View

/// One window in the switcher: crisp macOS squircle icon tile or AltTab-style
/// unified card with top icon+title header and continuous rounded preview.
final class WindowItemView: NSView {

    let info: WindowInfo
    let style: DisplayStyle
    var captionText: String {
        didSet {
            titleLabel.stringValue = captionText
            toolTip = captionText
        }
    }

    private let imageContainer = NSView()
    private let imageView = NSImageView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let pillBar = ActionPillBar()
    private let statusBadge = NSImageView()
    private let appIcon: NSImage?

    private var isShowingFallbackIcon = false
    private(set) var isSelected = false
    private var isFilteredOut = false

    var onActivate: (() -> Void)?
    var onHover: ((WindowItemView) -> Void)?
    var onClose: (() -> Void)?
    var onSnapLeft: (() -> Void)?
    var onSnapRight: (() -> Void)?
    var onSnapPopover: ((NSView) -> Void)?
    var onPin: (() -> Void)?

    private var tracking: NSTrackingArea?

    // MARK: - Init

    init(info: WindowInfo, caption: String, appIcon: NSImage?, style: DisplayStyle = .current) {
        self.info = info
        self.captionText = caption
        self.appIcon = appIcon
        self.style = style
        super.init(frame: .zero)

        toolTip = caption
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.cornerRadius = style == .iconsOnly ? Theme.iconTileCornerRadius : Theme.cardCornerRadius
        layer?.cornerCurve = .continuous

        imageContainer.wantsLayer = true
        imageContainer.layer?.masksToBounds = true
        imageContainer.layer?.cornerCurve = .continuous
        addSubview(imageContainer)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageContainer.addSubview(imageView)

        if style == .iconsOnly {
            imageContainer.layer?.cornerRadius = Theme.iconTileCornerRadius
            imageView.image = appIcon
            titleLabel.isHidden = true
            iconView.isHidden = true
        } else {
            imageContainer.layer?.cornerRadius = Theme.cellCornerRadius
            configureHeaderOrBadge(caption: caption)
        }

        // Hover Action Pill Bar (kept hidden unless pointer enters tile)
        pillBar.alphaValue = 0.0
        pillBar.isHidden = true
        pillBar.leftSplitButton.target = self
        pillBar.leftSplitButton.action = #selector(snapLeftClicked)
        pillBar.rightSplitButton.target = self
        pillBar.rightSplitButton.action = #selector(snapRightClicked)
        pillBar.snapPopoverButton.target = self
        pillBar.snapPopoverButton.action = #selector(snapPopoverClicked)
        pillBar.closeButton.target = self
        pillBar.closeButton.action = #selector(closeClicked)
        addSubview(pillBar)

        if info.browserTab != nil {
            statusBadge.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Browser tab")
            statusBadge.imageScaling = .scaleProportionallyUpOrDown
            statusBadge.contentTintColor = NSColor.systemTeal.withAlphaComponent(0.92)
            imageContainer.addSubview(statusBadge)
        } else if info.isMinimized {
            statusBadge.image = NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: "Minimized window")
            statusBadge.imageScaling = .scaleProportionallyUpOrDown
            statusBadge.contentTintColor = NSColor.systemYellow.withAlphaComponent(0.92)
            imageContainer.addSubview(statusBadge)
        }

        applyPalette()
    }

    private func configureHeaderOrBadge(caption: String) {
        iconView.image = appIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown

        if style == .full {
            addSubview(iconView)
            titleLabel.stringValue = caption
            titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
            titleLabel.textColor = Theme.captionText
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.maximumNumberOfLines = 1
            titleLabel.cell?.usesSingleLineMode = true
            titleLabel.alignment = .left
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addSubview(titleLabel)
        } else {
            // Subtle floating app icon over corner of thumbnail without harsh sticker frame
            imageContainer.addSubview(iconView)
            titleLabel.isHidden = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPalette()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    // MARK: - Content

    func setThumbnail(_ image: NSImage?) {
        guard style != .iconsOnly else {
            imageView.image = appIcon
            return
        }
        isShowingFallbackIcon = false
        imageView.image = image
        applyPalette()
        needsLayout = true
    }

    func showFallbackIcon() {
        isShowingFallbackIcon = true
        imageView.image = appIcon
        applyPalette()
        needsLayout = true
    }

    // MARK: - Selection state

    func setSelected(_ selected: Bool, filteredOut: Bool) {
        isSelected = selected
        isFilteredOut = filteredOut
        applyPalette()
    }

    func applyPalette() {
        let appearance = effectiveAppearance
        let thumb = imageContainer.layer

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if style == .iconsOnly {
            if isSelected {
                thumb?.backgroundColor = Theme.selectionFill.resolvedCGColor(for: appearance)
                let borderCol = Theme.selectionBorder.resolvedCGColor(for: appearance)
                thumb?.borderWidth = Theme.isNeutralHighlight ? 0 : 1.5
                thumb?.borderColor = Theme.isNeutralHighlight ? nil : borderCol
            } else {
                thumb?.backgroundColor = NSColor.clear.cgColor
                thumb?.borderWidth = 0
                thumb?.borderColor = nil
            }
            // Full 100% vivid icons (no dimming of unselected macOS icons)
            alphaValue = isFilteredOut ? Theme.filteredOutItemAlpha : 1.0
            CATransaction.commit()
            return
        }

        // Card container highlight plate for thumbnail modes (AltTab / Spotlight style)
        if isSelected {
            layer?.backgroundColor = Theme.selectionFill.resolvedCGColor(for: appearance)
            let ringCol = Theme.selectionBorder.resolvedCGColor(for: appearance)
            layer?.borderWidth = Theme.isNeutralHighlight ? 0 : 1.25
            layer?.borderColor = Theme.isNeutralHighlight ? nil : ringCol
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            layer?.borderColor = nil
        }

        let cardColor = isShowingFallbackIcon ? Theme.fallbackTileBackground : Theme.cardBackground
        thumb?.backgroundColor = cardColor.resolvedCGColor(for: appearance)
        thumb?.borderColor = Theme.cellBorder.resolvedCGColor(for: appearance)
        thumb?.borderWidth = 0.5

        alphaValue = isFilteredOut
            ? Theme.filteredOutItemAlpha
            : (isSelected ? Theme.selectedItemAlpha : Theme.idleItemAlpha)
        CATransaction.commit()

        if style == .full {
            let fontSize = max(10.0, min(11.5, bounds.height * 0.082))
            titleLabel.font = .systemFont(ofSize: fontSize, weight: isSelected ? .semibold : .medium)
            titleLabel.textColor = isSelected ? Theme.selectedCaptionText : Theme.captionText
        }
    }

    // MARK: - Layout

    static func captionHeight(for style: DisplayStyle) -> CGFloat {
        switch style {
        case .full:
            return 22
        case .thumbnailsOnly, .iconsOnly:
            return 0
        }
    }

    override func layout() {
        super.layout()

        if style == .iconsOnly {
            imageContainer.frame = bounds
            let iconSize = max(24, (min(bounds.width, bounds.height) * 0.78).rounded())
            imageView.frame = NSRect(
                x: ((bounds.width - iconSize) / 2).rounded(),
                y: ((bounds.height - iconSize) / 2).rounded(),
                width: iconSize,
                height: iconSize
            )
            titleLabel.isHidden = true
            iconView.isHidden = true

            let pillW = min(74, max(54, bounds.width - 8))
            let pillH: CGFloat = 20
            pillBar.frame = NSRect(
                x: ((bounds.width - pillW) / 2).rounded(),
                y: 4,
                width: pillW,
                height: pillH
            )

            if info.isMinimized || info.browserTab != nil {
                statusBadge.frame = NSRect(
                    x: 6,
                    y: max(0, bounds.height - 16),
                    width: 11,
                    height: 11
                )
            }
            return
        }

        let inset: CGFloat = 6
        let cHeight = Self.captionHeight(for: style)
        let innerW = max(0, bounds.width - inset * 2)

        if style == .full {
            // Top compact [Icon] Title bar cleanly above the screenshot
            let headerY = bounds.height - cHeight - 2
            let iconDim: CGFloat = 15
            iconView.isHidden = false
            iconView.frame = NSRect(
                x: inset + 2,
                y: headerY + ((cHeight - iconDim) / 2).rounded(),
                width: iconDim,
                height: iconDim
            )
            let labelX = iconView.frame.maxX + 6
            let labelH: CGFloat = 15
            titleLabel.frame = NSRect(
                x: labelX,
                y: headerY + ((cHeight - labelH) / 2).rounded(),
                width: max(0, bounds.width - inset - labelX),
                height: labelH
            )
        } else {
            iconView.isHidden = false
        }

        let thumbH = max(0, bounds.height - cHeight - inset * 2)
        imageContainer.frame = NSRect(
            x: inset,
            y: inset,
            width: innerW,
            height: thumbH
        )

        if isShowingFallbackIcon {
            let iconDim = max(24, min(60, (min(imageContainer.bounds.width, imageContainer.bounds.height) * 0.48).rounded()))
            imageView.frame = NSRect(
                x: ((imageContainer.bounds.width - iconDim) / 2).rounded(),
                y: ((imageContainer.bounds.height - iconDim) / 2).rounded(),
                width: iconDim,
                height: iconDim
            )
        } else {
            imageView.frame = imageContainer.bounds
        }

        if style == .thumbnailsOnly {
            let badgeDim = max(16, min(24, (min(innerW, thumbH) * 0.20).rounded()))
            iconView.frame = NSRect(x: 7, y: 7, width: badgeDim, height: badgeDim)
        }

        let pillW = min(90, max(62, innerW - 8))
        let pillH: CGFloat = bounds.width < 110 ? 20 : 23
        let pillX = imageContainer.frame.maxX - pillW - 5
        let pillY = imageContainer.frame.maxY - pillH - 5
        pillBar.frame = NSRect(x: pillX, y: pillY, width: pillW, height: pillH)

        if info.isMinimized || info.browserTab != nil {
            statusBadge.frame = NSRect(
                x: 6,
                y: max(6, imageContainer.bounds.height - 19),
                width: 13,
                height: 13
            )
        }
    }

    // MARK: - Interaction

    @objc private func snapLeftClicked() { onSnapLeft?() }
    @objc private func snapRightClicked() { onSnapRight?() }
    @objc private func snapPopoverClicked() { onSnapPopover?(pillBar.snapPopoverButton) }
    @objc private func pinClicked() { onPin?() }
    @objc private func closeClicked() { onClose?() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        let localPoint = convert(point, from: superview)

        if !pillBar.isHidden && pillBar.alphaValue > 0.05 {
            let pInPill = pillBar.convert(localPoint, from: self)
            if pillBar.bounds.contains(pInPill) {
                if pillBar.leftSplitButton.frame.contains(pInPill) { return pillBar.leftSplitButton }
                if pillBar.rightSplitButton.frame.contains(pInPill) { return pillBar.rightSplitButton }
                if pillBar.snapPopoverButton.frame.contains(pInPill) { return pillBar.snapPopoverButton }
                if pillBar.closeButton.frame.contains(pInPill) { return pillBar.closeButton }
                return pillBar
            }
        }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { onActivate?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        pillBar.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.pillBar.animator().alphaValue = 1.0
        }
        guard !isSelected else { return }
        onHover?(self)
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isSelected else { return }
        onHover?(self)
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.pillBar.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self, self.pillBar.alphaValue <= 0.05 else { return }
            self.pillBar.isHidden = true
        })
    }
}
