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

/// Apple-minimalist floating window preview triggered naturally when resting on a switcher icon
/// while holding the modifier key. Dynamically sizes from real window aspect ratio and anchors
/// cleanly above or below the switcher capsule without overlapping it.
final class QuickLookPanel: NSPanel {

    private let backgroundContainer = NSView()
    private let visualEffect = NSVisualEffectView()
    private let tintOverlay = NSView()

    private let headerIconView = NSImageView()
    private let headerTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        return label
    }()

    private let imageView = NSImageView()
    private let fallbackContainer = NSView()
    private let fallbackIconView = NSImageView()
    private let fallbackTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        return label
    }()
    private let fallbackSubtitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11.5, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        return label
    }()

    private(set) var currentWindow: WindowInfo?
    private var captureGeneration: Int = 0
    private var prewarmedImage: (id: CGWindowID, image: CGImage)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        buildUI()
        applyAppearancePreferences()
    }

    private func buildUI() {
        let root = NSView(frame: .zero)
        root.wantsLayer = true
        contentView = root

        backgroundContainer.wantsLayer = true
        backgroundContainer.layer?.cornerRadius = 16
        backgroundContainer.layer?.cornerCurve = .continuous
        backgroundContainer.layer?.masksToBounds = true
        backgroundContainer.layer?.borderWidth = Theme.panelBorderWidth
        root.addSubview(backgroundContainer)

        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        backgroundContainer.addSubview(visualEffect)

        tintOverlay.wantsLayer = true
        backgroundContainer.addSubview(tintOverlay)

        headerIconView.imageScaling = .scaleProportionallyUpOrDown
        root.addSubview(headerIconView)
        root.addSubview(headerTitleLabel)

        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        root.addSubview(imageView)

        fallbackContainer.isHidden = true
        fallbackIconView.imageScaling = .scaleProportionallyUpOrDown
        fallbackContainer.addSubview(fallbackIconView)
        fallbackContainer.addSubview(fallbackTitleLabel)
        fallbackContainer.addSubview(fallbackSubtitleLabel)
        root.addSubview(fallbackContainer)
    }

    func applyAppearancePreferences() {
        appearance = AppearancePreferences.theme.nsAppearance
        let effective = contentView?.effectiveAppearance ?? NSAppearance.currentDrawing()
        backgroundContainer.layer?.borderColor = Theme.panelBorder.resolvedCGColor(for: effective)
        tintOverlay.layer?.backgroundColor = Theme.panelBackingColor(for: effective).cgColor

        switch AppearancePreferences.backgroundStyle {
        case .frosted:
            visualEffect.isHidden = false
            visualEffect.material = .popover
            visualEffect.alphaValue = max(0.35, CGFloat(AppearancePreferences.panelOpacity))
        case .clear:
            visualEffect.isHidden = false
            visualEffect.material = .hudWindow
            visualEffect.alphaValue = max(0.10, CGFloat(AppearancePreferences.panelOpacity) * 0.35)
        case .tinted:
            visualEffect.isHidden = true
        }
    }

    // MARK: - Pre-warming & Presentation

    /// Starts capturing the preview image silently before the dwell threshold completes
    /// so the screenshot appears instantaneously on frame 1 when the panel fades in.
    func prewarm(for window: WindowInfo, on screen: NSScreen) {
        guard Permissions.screenRecordingGranted, window.id > 0, window.browserTab == nil else {
            prewarmedImage = nil
            return
        }
        if prewarmedImage?.id == window.id { return }

        let targetID = window.id
        let maxPx = maxCapturePixelSize(for: window, on: screen)
        Task { [weak self] in
            let cg = await ThumbnailService.shared.thumbnail(windowID: targetID, pixelSize: maxPx, tier: .preview)
            await MainActor.run {
                guard let self, let cg else { return }
                self.prewarmedImage = (targetID, cg)
            }
        }
    }

    func show(
        for window: WindowInfo,
        on screen: NSScreen,
        anchorRect: NSRect?,
        switcherFrame: NSRect
    ) {
        applyAppearancePreferences()
        currentWindow = window
        updateContent(for: window, on: screen, anchorRect: anchorRect, switcherFrame: switcherFrame)

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    func update(
        for window: WindowInfo,
        on screen: NSScreen,
        anchorRect: NSRect?,
        switcherFrame: NSRect
    ) {
        guard isVisible else { return }
        applyAppearancePreferences()
        if currentWindow?.id == window.id && currentWindow?.pid == window.pid {
            return
        }
        currentWindow = window
        updateContent(for: window, on: screen, anchorRect: anchorRect, switcherFrame: switcherFrame)
    }

    /// Synchronous zero-delay removal when releasing the modifier key.
    func hideImmediately() {
        captureGeneration += 1
        currentWindow = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        orderOut(nil)
        CATransaction.commit()
        CATransaction.flush()
    }

    func hideAnimated() {
        captureGeneration += 1
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.currentWindow = nil
        })
    }

    func toggle(
        for window: WindowInfo,
        on screen: NSScreen,
        anchorRect: NSRect?,
        switcherFrame: NSRect
    ) {
        if isVisible {
            hideAnimated()
        } else {
            show(for: window, on: screen, anchorRect: anchorRect, switcherFrame: switcherFrame)
        }
    }

    // MARK: - Content & Sizing

    private func updateContent(
        for window: WindowInfo,
        on screen: NSScreen,
        anchorRect: NSRect?,
        switcherFrame: NSRect
    ) {
        captureGeneration += 1
        let gen = captureGeneration
        let appIcon = IconCache.shared.icon(bundleID: window.bundleID, pid: window.pid)
        let displayTitle = resolvedTitle(for: window)

        headerIconView.image = appIcon
        headerTitleLabel.stringValue = displayTitle

        // Non-capturable targets (windowless apps, virtual browser tabs, or missing permission)
        // render cleanly as compact native info cards rather than stretched icons.
        let canCaptureWindow = Permissions.screenRecordingGranted && window.id > 0 && window.browserTab == nil
        if !canCaptureWindow {
            showFallbackCard(for: window, icon: appIcon, title: displayTitle, on: screen, anchorRect: anchorRect, switcherFrame: switcherFrame)
            return
        }

        // Fast path: prewarmed CGImage is already ready in memory (0ms instant preview!)
        if let cached = prewarmedImage, cached.id == window.id {
            showImagePreview(cgImage: cached.image, for: window, on: screen, anchorRect: anchorRect, switcherFrame: switcherFrame)
            return
        }

        // Size frame cleanly to real aspect while capture completes (~50-120ms)
        fallbackContainer.isHidden = true
        headerIconView.isHidden = false
        headerTitleLabel.isHidden = false
        imageView.isHidden = false
        imageView.image = nil
        layoutPreviewFrame(
            aspect: window.aspectRatio,
            isFallback: false,
            on: screen,
            anchorRect: anchorRect,
            switcherFrame: switcherFrame
        )

        let targetID = window.id
        let maxPx = maxCapturePixelSize(for: window, on: screen)
        Task { [weak self] in
            let cg = await ThumbnailService.shared.thumbnail(windowID: targetID, pixelSize: maxPx, tier: .preview)
            await MainActor.run {
                guard let self, self.captureGeneration == gen, self.currentWindow?.id == targetID else { return }
                if let cg {
                    self.prewarmedImage = (targetID, cg)
                    self.showImagePreview(
                        cgImage: cg,
                        for: window,
                        on: screen,
                        anchorRect: anchorRect,
                        switcherFrame: switcherFrame
                    )
                } else {
                    self.showFallbackCard(
                        for: window,
                        icon: appIcon,
                        title: displayTitle,
                        on: screen,
                        anchorRect: anchorRect,
                        switcherFrame: switcherFrame
                    )
                }
            }
        }
    }

    private func showImagePreview(
        cgImage: CGImage,
        for window: WindowInfo,
        on screen: NSScreen,
        anchorRect: NSRect?,
        switcherFrame: NSRect
    ) {
        fallbackContainer.isHidden = true
        headerIconView.isHidden = false
        headerTitleLabel.isHidden = false
        imageView.isHidden = false

        let aspect = cgImage.height > 0 ? CGFloat(cgImage.width) / CGFloat(cgImage.height) : window.aspectRatio
        layoutPreviewFrame(
            aspect: aspect,
            isFallback: false,
            on: screen,
            anchorRect: anchorRect,
            switcherFrame: switcherFrame
        )
        let backing = screen.backingScaleFactor
        let pointSize = NSSize(width: CGFloat(cgImage.width) / backing, height: CGFloat(cgImage.height) / backing)
        imageView.image = NSImage(cgImage: cgImage, size: pointSize)
    }

    private func showFallbackCard(
        for window: WindowInfo,
        icon: NSImage?,
        title: String,
        on screen: NSScreen,
        anchorRect: NSRect?,
        switcherFrame: NSRect
    ) {
        imageView.isHidden = true
        imageView.image = nil
        headerIconView.isHidden = true
        headerTitleLabel.isHidden = true
        fallbackContainer.isHidden = false

        fallbackIconView.image = icon
        fallbackTitleLabel.stringValue = window.ownerName
        if let tab = window.browserTab {
            fallbackSubtitleLabel.stringValue = tab.domain.isEmpty ? tab.browserName : "\(tab.browserName) · \(tab.domain)"
            fallbackTitleLabel.stringValue = title
        } else if window.isMinimized {
            fallbackSubtitleLabel.stringValue = title == window.ownerName ? "Minimized window" : title
        } else if window.id == 0 {
            fallbackSubtitleLabel.stringValue = "No open window · Release to reopen"
        } else {
            fallbackSubtitleLabel.stringValue = title
        }

        layoutPreviewFrame(
            aspect: 1.6,
            isFallback: true,
            on: screen,
            anchorRect: anchorRect,
            switcherFrame: switcherFrame
        )
    }

    private func resolvedTitle(for window: WindowInfo) -> String {
        if let tab = window.browserTab {
            let trimmed = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? tab.domain : trimmed
        }
        let trimmed = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? window.ownerName : trimmed
    }

    private func maxCapturePixelSize(for window: WindowInfo, on screen: NSScreen) -> CGSize {
        let vf = screen.visibleFrame
        let scale = max(2.0, screen.backingScaleFactor)
        let maxW = min(680, vf.width * 0.48) * scale
        let maxH = min(440, vf.height * 0.46) * scale
        return CGSize(width: maxW, height: maxH)
    }

    private func layoutPreviewFrame(
        aspect: CGFloat,
        isFallback: Bool,
        on screen: NSScreen,
        anchorRect: NSRect?,
        switcherFrame: NSRect
    ) {
        let vf = screen.visibleFrame
        let gap: CGFloat = 14
        let edgeMargin: CGFloat = 20

        let spaceAbove = max(0, vf.maxY - switcherFrame.maxY - gap - edgeMargin)
        let spaceBelow = max(0, switcherFrame.minY - vf.minY - gap - edgeMargin)
        let placeAbove = spaceAbove >= 220 || spaceAbove >= spaceBelow
        let availVertical = max(120, placeAbove ? spaceAbove : spaceBelow)

        let panelSize: NSSize
        if isFallback {
            panelSize = NSSize(width: 300, height: 74)
        } else {
            let padX: CGFloat = 10
            let headerH: CGFloat = 28
            let padBottom: CGFloat = 10
            let safeAspect = max(0.45, min(2.6, aspect))

            let maxImgW = min(680, vf.width * 0.48) - padX * 2
            let maxImgH = min(min(440, vf.height * 0.46), availVertical) - headerH - padBottom
            let clampedMaxImgH = max(120, maxImgH)

            var imgW = maxImgW
            var imgH = (imgW / safeAspect).rounded()
            if imgH > clampedMaxImgH {
                imgH = clampedMaxImgH
                imgW = (imgH * safeAspect).rounded()
            }
            if imgW > maxImgW {
                imgW = maxImgW
                imgH = (imgW / safeAspect).rounded()
            }
            imgW = max(220, imgW)
            imgH = max(120, imgH)

            panelSize = NSSize(
                width: (imgW + padX * 2).rounded(),
                height: (imgH + headerH + padBottom).rounded()
            )
        }

        let targetCenterX = anchorRect?.midX ?? switcherFrame.midX
        let rawX = targetCenterX - panelSize.width / 2
        let clampedX = min(
            max(vf.minX + edgeMargin, rawX),
            vf.maxX - panelSize.width - edgeMargin
        )

        let y: CGFloat = placeAbove
            ? min(vf.maxY - panelSize.height - edgeMargin, switcherFrame.maxY + gap)
            : max(vf.minY + edgeMargin, switcherFrame.minY - gap - panelSize.height)

        let targetFrame = NSRect(x: clampedX.rounded(), y: y.rounded(), width: panelSize.width, height: panelSize.height)
        setFrame(targetFrame, display: true, animate: false)
        layoutInternalSubviews(for: panelSize, isFallback: isFallback)
    }

    private func layoutInternalSubviews(for size: NSSize, isFallback: Bool) {
        let bounds = NSRect(origin: .zero, size: size)
        contentView?.frame = bounds
        backgroundContainer.frame = bounds
        visualEffect.frame = backgroundContainer.bounds
        tintOverlay.frame = backgroundContainer.bounds

        if isFallback {
            fallbackContainer.frame = bounds
            let iconDim: CGFloat = 40
            let padX: CGFloat = 16
            fallbackIconView.frame = NSRect(
                x: padX,
                y: ((size.height - iconDim) / 2).rounded(),
                width: iconDim,
                height: iconDim
            )
            let textX = fallbackIconView.frame.maxX + 12
            let textW = max(80, size.width - textX - padX)
            fallbackTitleLabel.frame = NSRect(x: textX, y: size.height / 2 + 1, width: textW, height: 18)
            fallbackSubtitleLabel.frame = NSRect(x: textX, y: size.height / 2 - 17, width: textW, height: 16)
            return
        }

        let padX: CGFloat = 10
        let padBottom: CGFloat = 10
        let headerH: CGFloat = 28

        let iconSize: CGFloat = 15
        headerIconView.frame = NSRect(
            x: padX + 2,
            y: size.height - headerH + ((headerH - iconSize) / 2).rounded(),
            width: iconSize,
            height: iconSize
        )
        let titleX = headerIconView.frame.maxX + 6
        headerTitleLabel.frame = NSRect(
            x: titleX,
            y: size.height - headerH + ((headerH - 16) / 2).rounded(),
            width: max(40, size.width - padX - titleX),
            height: 16
        )

        imageView.frame = NSRect(
            x: padX,
            y: padBottom,
            width: max(40, size.width - padX * 2),
            height: max(40, size.height - headerH - padBottom)
        )
    }
}
