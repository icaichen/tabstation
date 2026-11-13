import AppKit

/// A clickable mini-display tile that visually represents a window snap zone.
final class SnapTileView: NSControl {

    let zone: WindowGridManager.SnapZone
    private var isHovered = false
    private var tracking: NSTrackingArea?

    init(zone: WindowGridManager.SnapZone) {
        self.zone = zone
        super.init(frame: NSRect(x: 0, y: 0, width: 40, height: 28))
        wantsLayer = true
        toolTip = zone.displayName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 40, height: 28)
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
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let b = bounds.insetBy(dx: 2, dy: 2)

        // Outer display bezel
        let bezelPath = NSBezierPath(roundedRect: b, xRadius: 4, yRadius: 4)
        if isHovered {
            NSColor.white.withAlphaComponent(0.18).setFill()
            bezelPath.fill()
            Theme.accent.withAlphaComponent(0.85).setStroke()
            bezelPath.lineWidth = 1.2
        } else {
            NSColor.black.withAlphaComponent(0.35).setFill()
            bezelPath.fill()
            NSColor.white.withAlphaComponent(0.20).setStroke()
            bezelPath.lineWidth = 0.8
        }
        bezelPath.stroke()

        // Inner screen area (excluding bezel border)
        let inner = b.insetBy(dx: 2, dy: 2)
        let zoneRect = calculateInnerZoneRect(for: zone, in: inner)

        // Draw active snap zone highlight
        let highlightPath = NSBezierPath(roundedRect: zoneRect, xRadius: 2.5, yRadius: 2.5)
        if isHovered {
            Theme.accent.setFill()
        } else {
            Theme.accent.withAlphaComponent(0.70).setFill()
        }
        highlightPath.fill()
    }

    private func calculateInnerZoneRect(for zone: WindowGridManager.SnapZone, in r: CGRect) -> CGRect {
        let x = r.origin.x
        let y = r.origin.y
        let w = r.width
        let h = r.height

        let halfW = (w / 2).rounded()
        let halfH = (h / 2).rounded()
        let thirdW = (w / 3).rounded()
        let twoThirdsW = (w * 2 / 3).rounded()

        switch zone {
        case .leftHalf:
            return CGRect(x: x, y: y, width: halfW, height: h)
        case .rightHalf:
            return CGRect(x: x + halfW, y: y, width: w - halfW, height: h)
        case .topHalf:
            return CGRect(x: x, y: y + halfH, width: w, height: h - halfH)
        case .bottomHalf:
            return CGRect(x: x, y: y, width: w, height: halfH)
        case .maximize:
            return r
        case .center:
            return r.insetBy(dx: w * 0.18, dy: h * 0.18)
        case .leftThird:
            return CGRect(x: x, y: y, width: thirdW, height: h)
        case .leftTwoThirds:
            return CGRect(x: x, y: y, width: twoThirdsW, height: h)
        case .rightTwoThirds:
            return CGRect(x: x + (w - twoThirdsW), y: y, width: twoThirdsW, height: h)
        case .rightThird:
            return CGRect(x: x + (w - thirdW), y: y, width: thirdW, height: h)
        case .topLeftQuarter:
            return CGRect(x: x, y: y + halfH, width: halfW, height: h - halfH)
        case .topRightQuarter:
            return CGRect(x: x + halfW, y: y + halfH, width: w - halfW, height: h - halfH)
        case .bottomLeftQuarter:
            return CGRect(x: x, y: y, width: halfW, height: halfH)
        case .bottomRightQuarter:
            return CGRect(x: x + halfW, y: y, width: w - halfW, height: halfH)
        }
    }
}

/// Content view of the Snap Popover displaying visual grid sections.
final class WindowSnapContentView: NSView {

    var onSelectZone: ((WindowGridManager.SnapZone) -> Void)?
    private let titleLabel = NSTextField(labelWithString: "Window Snapping")

    init(windowTitle: String) {
        super.init(frame: .zero)
        wantsLayer = true
        buildUI(windowTitle: windowTitle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildUI(windowTitle: String) {
        // Frosted HUD Vibrancy
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        addSubview(effect)
        effect.autoresizingMask = [.width, .height]

        let titleText = windowTitle.isEmpty ? "Snap Window" : windowTitle
        titleLabel.stringValue = titleText
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .center
        addSubview(titleLabel)

        // Section 1: Halves & Full
        let halvesStack = createTilesStack(zones: [
            .leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .center
        ])

        // Section 2: Thirds
        let thirdsStack = createTilesStack(zones: [
            .leftThird, .leftTwoThirds, .rightTwoThirds, .rightThird
        ])

        // Section 3: Quarters
        let quartersStack = createTilesStack(zones: [
            .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter
        ])

        let labelHalves = makeSectionLabel("Halves & Full")
        let labelThirds = makeSectionLabel("Thirds")
        let labelQuarters = makeSectionLabel("Corners")

        let mainStack = NSStackView(views: [
            titleLabel,
            labelHalves,
            halvesStack,
            labelThirds,
            thirdsStack,
            labelQuarters,
            quartersStack
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 6
        mainStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        addSubview(mainStack)
        mainStack.autoresizingMask = [.width, .height]
    }

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.8)
        return label
    }

    private func createTilesStack(zones: [WindowGridManager.SnapZone]) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.distribution = .gravityAreas

        for zone in zones {
            let tile = SnapTileView(zone: zone)
            tile.target = self
            tile.action = #selector(tileClicked(_:))
            stack.addArrangedSubview(tile)
        }
        return stack
    }

    @objc private func tileClicked(_ sender: SnapTileView) {
        onSelectZone?(sender.zone)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 284, height: 216)
    }
}

/// Floating HUD panel for clicking window snap tiles.
final class WindowSnapPanel: NSPanel {

    static let shared = WindowSnapPanel()

    private var targetWindow: WindowInfo?
    var onSnapped: ((String) -> Void)?

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 284, height: 216),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    func show(for window: WindowInfo, relativeTo anchorView: NSView, targetScreen: NSScreen? = nil) {
        self.targetWindow = window
        let content = WindowSnapContentView(windowTitle: window.title.isEmpty ? window.ownerName : window.title)
        content.onSelectZone = { [weak self] zone in
            guard let self, let win = self.targetWindow else { return }
            let screen = targetScreen ?? anchorView.window?.screen ?? NSScreen.main
            let msg = WindowGridManager.snap(window: win, to: zone, targetScreen: screen)
            self.onSnapped?(msg)
            self.closeAnimated()
        }
        contentView = content

        // Position panel directly below or above the anchor view
        guard let win = anchorView.window else { return }
        let viewRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let screenRect = win.convertToScreen(viewRectInWindow)

        let size = content.intrinsicContentSize
        var originX = screenRect.midX - size.width / 2
        var originY = screenRect.minY - size.height - 8

        // Screen boundary safety
        if let screen = win.screen ?? NSScreen.main {
            let vf = screen.visibleFrame
            originX = max(vf.minX + 10, min(originX, vf.maxX - size.width - 10))
            if originY < vf.minY + 10 {
                // Flip to above if below bounds
                originY = screenRect.maxY + 8
            }
        }

        setFrame(NSRect(x: originX.rounded(), y: originY.rounded(), width: size.width, height: size.height), display: true)
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }

    func closeAnimated() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.targetWindow = nil
        })
    }
}
