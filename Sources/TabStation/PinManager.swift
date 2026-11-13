import AppKit
import ScreenCaptureKit
import WebKit

/// The content view for a pinned Picture-in-Picture window.
/// Supports both:
/// 1. Interactive Live Web Mode (embedded WebKit with full media/document controls for YouTube, docs, web apps)
/// 2. Interactive Window Mirror Mode (live window capture with direct mouse click & scroll forwarding to any native app)
final class PinnedWindowContentView: NSView {

    let windowInfo: WindowInfo
    let webURL: URL?

    private let visualEffect = NSVisualEffectView()
    private let titleBar = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    private let ghostButton = NSButton()
    private let opacityButton = NSButton()
    private let modeButton = NSButton()
    private let focusButton = NSButton()
    private let closeButton = NSButton()

    private let imageView = NSImageView()
    private var webView: WKWebView?

    private var refreshTimer: Timer?
    var onClose: (() -> Void)?
    var onGhostToggled: ((Bool) -> Void)?

    private(set) var isGhostMode = false
    private(set) var isWebMode = false

    private let opacityLevels: [CGFloat] = [1.0, 0.80, 0.55, 0.35]
    private var currentOpacityIndex = 0

    init(window: WindowInfo) {
        self.windowInfo = window

        // Detect if this window is or contains a web URL
        var resolvedURL: URL? = nil
        if let tabUrl = window.browserTab?.url, let u = URL(string: tabUrl) {
            resolvedURL = u
        } else if let activeUrlStr = BrowserTabService.queryActiveURL(for: window.pid), let u = URL(string: activeUrlStr) {
            resolvedURL = u
        }
        self.webURL = resolvedURL
        // Default to Web View for web URLs, especially YouTube / documents
        self.isWebMode = (resolvedURL != nil)

        super.init(frame: .zero)
        buildUI()
        if !isWebMode {
            startRefreshing()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildUI() {
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        addSubview(visualEffect)

        // Title bar
        titleBar.wantsLayer = true
        titleBar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor

        iconView.image = NSRunningApplication(processIdentifier: windowInfo.pid)?.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleBar.addSubview(iconView)

        let initialTitle = windowInfo.title.isEmpty ? windowInfo.ownerName : windowInfo.title
        titleLabel.stringValue = initialTitle
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleBar.addSubview(titleLabel)

        // Ghost mode button (Click-through)
        ghostButton.isBordered = false
        ghostButton.bezelStyle = .regularSquare
        ghostButton.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "Ghost Mode (Click-Through)")
        ghostButton.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        ghostButton.toolTip = "Ghost Mode (Click-Through)\nAllows clicking through this PiP window to apps behind it"
        ghostButton.target = self
        ghostButton.action = #selector(toggleGhostMode)
        titleBar.addSubview(ghostButton)

        // Opacity cycle button
        opacityButton.isBordered = false
        opacityButton.bezelStyle = .regularSquare
        opacityButton.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Adjust Opacity")
        opacityButton.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        opacityButton.toolTip = "Opacity: 100%\nClick to cycle (100% -> 80% -> 55% -> 35%)\nOr scroll wheel over title bar to fine-tune"
        opacityButton.target = self
        opacityButton.action = #selector(cycleOpacity)
        titleBar.addSubview(opacityButton)

        // Mode switch button (Live Web View vs Window Mirror)
        if webURL != nil {
            modeButton.isBordered = false
            modeButton.bezelStyle = .regularSquare
            modeButton.image = NSImage(systemSymbolName: isWebMode ? "globe" : "macwindow.on.rectangle", accessibilityDescription: "Toggle Mode")
            modeButton.contentTintColor = isWebMode ? NSColor.systemTeal : NSColor.white.withAlphaComponent(0.8)
            modeButton.toolTip = isWebMode
                ? "Live Web View (Interactive)\nClick to switch to Window Mirror"
                : "Window Mirror (Click-Forwarding)\nClick to switch to Live Web View"
            modeButton.target = self
            modeButton.action = #selector(toggleMode)
            titleBar.addSubview(modeButton)
        } else {
            modeButton.isHidden = true
        }

        // Focus original window
        focusButton.isBordered = false
        focusButton.bezelStyle = .regularSquare
        focusButton.image = NSImage(systemSymbolName: "arrow.up.forward.app.fill", accessibilityDescription: "Focus Original Window")
        focusButton.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        focusButton.toolTip = "Focus Original Window (Double-click anywhere)"
        focusButton.target = self
        focusButton.action = #selector(focusOriginalWindow)
        titleBar.addSubview(focusButton)

        // Close PiP
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close PiP")
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        closeButton.toolTip = "Close PiP"
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        titleBar.addSubview(closeButton)

        visualEffect.addSubview(titleBar)

        // Setup Main Preview Image (for Mirror Mode)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        visualEffect.addSubview(imageView)

        // Setup WebKit View (for Live Web Mode)
        if let url = webURL {
            let config = WKWebViewConfiguration()
            config.allowsAirPlayForMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []
            let web = WKWebView(frame: .zero, configuration: config)
            web.allowsBackForwardNavigationGestures = true
            web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
            web.load(URLRequest(url: url))
            web.wantsLayer = true
            visualEffect.addSubview(web)
            self.webView = web
        }

        updateDisplayModeVisibility()
        updateThumbnail()
    }

    override func layout() {
        super.layout()
        visualEffect.frame = bounds
        let b = bounds
        let barHeight: CGFloat = 26

        titleBar.frame = NSRect(x: 0, y: b.height - barHeight, width: b.width, height: barHeight)
        iconView.frame = NSRect(x: 7, y: 5, width: 16, height: 16)

        let btnSize: CGFloat = 18
        let btnY: CGFloat = 4
        let spacing: CGFloat = 4

        closeButton.frame = NSRect(x: max(0, b.width - 24), y: btnY, width: btnSize, height: btnSize)
        focusButton.frame = NSRect(x: max(0, closeButton.frame.minX - btnSize - spacing), y: btnY, width: btnSize, height: btnSize)

        var lastBtnMinX = focusButton.frame.minX
        if !modeButton.isHidden {
            modeButton.frame = NSRect(x: max(0, lastBtnMinX - btnSize - spacing), y: btnY, width: btnSize, height: btnSize)
            lastBtnMinX = modeButton.frame.minX
        }

        opacityButton.frame = NSRect(x: max(0, lastBtnMinX - btnSize - spacing), y: btnY, width: btnSize, height: btnSize)
        ghostButton.frame = NSRect(x: max(0, opacityButton.frame.minX - btnSize - spacing), y: btnY, width: btnSize, height: btnSize)

        let rightEdgeOfTitle = ghostButton.frame.minX - 6
        titleLabel.frame = NSRect(x: 28, y: 5, width: max(0, rightEdgeOfTitle - 28), height: 16)

        let contentFrame = NSRect(x: 0, y: 0, width: b.width, height: max(0, b.height - barHeight))
        imageView.frame = contentFrame
        webView?.frame = contentFrame
    }

    private func updateDisplayModeVisibility() {
        if isWebMode, let webView {
            webView.isHidden = false
            imageView.isHidden = true
            refreshTimer?.invalidate()
            refreshTimer = nil
            modeButton.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Live Web Mode")
            modeButton.contentTintColor = NSColor.systemTeal
            modeButton.toolTip = "Live Web View (Interactive)\nClick to switch to Window Mirror"
        } else {
            webView?.isHidden = true
            imageView.isHidden = false
            modeButton.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Window Mirror Mode")
            modeButton.contentTintColor = NSColor.white.withAlphaComponent(0.8)
            modeButton.toolTip = "Window Mirror (Click-Forwarding)\nClick to switch to Live Web View"
            startRefreshing()
        }
    }

    @objc private func toggleMode() {
        guard webURL != nil else { return }
        isWebMode.toggle()
        updateDisplayModeVisibility()
        if !isWebMode {
            updateThumbnail()
        }
    }

    // MARK: - Live Capture & Fast Refresh

    private func startRefreshing() {
        guard !isWebMode else { return }
        updateThumbnail()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.updateThumbnail()
        }
    }

    private func triggerFastRefresh() {
        guard !isWebMode else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.updateThumbnail()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.updateThumbnail()
        }
    }

    private func updateThumbnail() {
        guard !isWebMode else { return }
        let size = CGSize(width: max(200, bounds.width * 2), height: max(140, bounds.height * 2))
        Task { [weak self] in
            guard let self else { return }
            let image = await ThumbnailService.shared.thumbnail(windowID: self.windowInfo.id, pixelSize: size)
            await MainActor.run {
                if let image {
                    self.imageView.image = NSImage(cgImage: image, size: .zero)
                } else if self.imageView.image == nil {
                    self.imageView.image = NSRunningApplication(processIdentifier: self.windowInfo.pid)?.icon
                }
            }
        }
    }

    // MARK: - Direct Mouse Event Forwarding (Universal)

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if titleBar.frame.contains(loc) {
            super.mouseDown(with: event)
            return
        }

        if event.clickCount >= 2 {
            focusOriginalWindow()
            return
        }

        if !isWebMode {
            forwardMouseEvent(event: event, isDown: true)
            showClickRipple(at: loc)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if titleBar.frame.contains(loc) {
            super.mouseUp(with: event)
            return
        }

        if !isWebMode {
            forwardMouseEvent(event: event, isDown: false)
            triggerFastRefresh()
        } else {
            super.mouseUp(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if titleBar.frame.contains(loc) {
            guard let win = window else { return }
            let delta = event.scrollingDeltaY * 0.02
            let newAlpha = min(1.0, max(0.25, win.alphaValue + delta))
            win.alphaValue = newAlpha
            opacityButton.toolTip = "Opacity: \(Int(newAlpha * 100))%\nClick to cycle\nOr scroll wheel over title bar to fine-tune"
            return
        }

        if !isWebMode {
            forwardScrollEvent(event: event)
            triggerFastRefresh()
        } else {
            super.scrollWheel(with: event)
        }
    }

    private func forwardMouseEvent(event: NSEvent, isDown: Bool) {
        let loc = convert(event.locationInWindow, from: nil)
        guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }

        // Convert PiP view coordinates to real window Quartz screen coordinates
        let normX = max(0, min(1, loc.x / imageView.bounds.width))
        let normY = max(0, min(1, 1.0 - (loc.y / imageView.bounds.height)))

        let targetX = windowInfo.bounds.minX + normX * windowInfo.bounds.width
        let targetY = windowInfo.bounds.minY + normY * windowInfo.bounds.height
        let targetPt = CGPoint(x: targetX.rounded(), y: targetY.rounded())

        let source = CGEventSource(stateID: .combinedSessionState)
        let eventType: CGEventType = isDown ? .leftMouseDown : .leftMouseUp

        if let evt = CGEvent(mouseEventSource: source, mouseType: eventType, mouseCursorPosition: targetPt, mouseButton: .left) {
            evt.setIntegerValueField(.mouseEventClickState, value: Int64(max(1, event.clickCount)))
            evt.postToPid(windowInfo.pid)
            evt.post(tap: .cghidEventTap)
        }
    }

    private func forwardScrollEvent(event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }

        let normX = max(0, min(1, loc.x / imageView.bounds.width))
        let normY = max(0, min(1, 1.0 - (loc.y / imageView.bounds.height)))

        let targetX = windowInfo.bounds.minX + normX * windowInfo.bounds.width
        let targetY = windowInfo.bounds.minY + normY * windowInfo.bounds.height
        let targetPt = CGPoint(x: targetX.rounded(), y: targetY.rounded())

        let source = CGEventSource(stateID: .combinedSessionState)
        let deltaY = Int32(event.scrollingDeltaY * 6)
        let deltaX = Int32(event.scrollingDeltaX * 6)

        if let scrollEvt = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0) {
            scrollEvt.location = targetPt
            scrollEvt.postToPid(windowInfo.pid)
            scrollEvt.post(tap: .cghidEventTap)
        }
    }

    private func showClickRipple(at point: NSPoint) {
        let ripple = CAShapeLayer()
        let radius: CGFloat = 16
        ripple.path = CGPath(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2), transform: nil)
        ripple.fillColor = NSColor.systemTeal.withAlphaComponent(0.35).cgColor
        ripple.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        ripple.lineWidth = 1.0
        layer?.addSublayer(ripple)

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            ripple.removeFromSuperlayer()
        }
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.5
        scaleAnim.toValue = 1.4
        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = 1.0
        fadeAnim.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scaleAnim, fadeAnim]
        group.duration = 0.22
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ripple.add(group, forKey: "ripple")
        CATransaction.commit()
    }

    // MARK: - Ghost Mode & Opacity

    @objc private func toggleGhostMode() {
        guard let win = window else { return }
        isGhostMode.toggle()
        win.ignoresMouseEvents = isGhostMode
        if isGhostMode {
            ghostButton.contentTintColor = NSColor.systemTeal
            win.alphaValue = min(win.alphaValue, 0.65)
        } else {
            ghostButton.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        }
        onGhostToggled?(isGhostMode)
    }

    func setGhostMode(_ active: Bool) {
        guard let win = window else { return }
        isGhostMode = active
        win.ignoresMouseEvents = active
        ghostButton.contentTintColor = active ? NSColor.systemTeal : NSColor.white.withAlphaComponent(0.8)
        if active {
            win.alphaValue = min(win.alphaValue, 0.65)
        }
    }

    @objc private func cycleOpacity() {
        currentOpacityIndex = (currentOpacityIndex + 1) % opacityLevels.count
        let alpha = opacityLevels[currentOpacityIndex]
        window?.alphaValue = alpha
        opacityButton.toolTip = "Opacity: \(Int(alpha * 100))%\nClick to cycle\nOr scroll wheel over title bar to fine-tune"
    }

    @objc private func focusOriginalWindow() {
        WindowActivator.activate(windowInfo)
    }

    @objc private func closeClicked() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        onClose?()
    }

    deinit {
        refreshTimer?.invalidate()
    }
}

/// A floating Picture-in-Picture (PiP) window that stays always-on-top across
/// all spaces and full-screen applications, mirroring a pinned window.
final class PinnedWindowPanel: NSPanel {

    let windowInfo: WindowInfo
    private let pinContentView: PinnedWindowContentView

    var isGhostMode: Bool {
        pinContentView.isGhostMode
    }

    func setGhostMode(_ active: Bool) {
        pinContentView.setGhostMode(active)
    }

    var onClose: (() -> Void)? {
        get { pinContentView.onClose }
        set {
            pinContentView.onClose = { [weak self] in
                newValue?()
                self?.close()
            }
        }
    }

    init(window: WindowInfo, on screen: NSScreen) {
        self.windowInfo = window
        self.pinContentView = PinnedWindowContentView(window: window)

        let aspect = window.aspectRatio
        let width: CGFloat = 360
        let height: CGFloat = (width / aspect).rounded() + 28

        let vf = screen.visibleFrame
        let initialX = vf.maxX - width - 24
        let initialY = vf.maxY - height - 36

        super.init(
            contentRect: NSRect(x: initialX, y: initialY, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        minSize = NSSize(width: 240, height: 160)
        maxSize = NSSize(width: 1100, height: 780)
        aspectRatio = NSSize(width: width, height: height)
        contentView = pinContentView
    }
}

/// Manages pinned Picture-in-Picture floating windows.
final class PinManager {

    static let shared = PinManager()

    private var pinnedPanels: [CGWindowID: PinnedWindowPanel] = [:]

    var hasPinnedWindows: Bool {
        !pinnedPanels.isEmpty
    }

    var hasGhostWindows: Bool {
        pinnedPanels.values.contains { $0.isGhostMode }
    }

    func isPinned(_ windowID: CGWindowID) -> Bool {
        pinnedPanels[windowID] != nil
    }

    @discardableResult
    func togglePin(for window: WindowInfo, on screen: NSScreen) -> (isPinned: Bool, message: String) {
        if let existing = pinnedPanels[window.id] {
            existing.close()
            pinnedPanels.removeValue(forKey: window.id)
            return (false, "Unpinned \(window.ownerName)")
        }

        let panel = PinnedWindowPanel(window: window, on: screen)
        panel.onClose = { [weak self] in
            self?.pinnedPanels.removeValue(forKey: window.id)
        }
        panel.orderFrontRegardless()
        pinnedPanels[window.id] = panel
        return (true, "Pinned \(window.ownerName) to PiP")
    }

    func disableGhostModeForAll() {
        for panel in pinnedPanels.values {
            panel.setGhostMode(false)
        }
    }

    func unpinAll() {
        pinnedPanels.values.forEach { $0.close() }
        pinnedPanels.removeAll()
    }
}
