import AppKit
import CoreMedia
import ScreenCaptureKit
import VideoToolbox

/// Streams live ScreenCaptureKit video frames (`SCStream`) for a single pinned window on demand.
/// Zero background overhead when PiP is closed; ScreenCaptureKit only emits frames on visual updates.
private final class LiveMirrorStream: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

    private let outputQueue = DispatchQueue(label: "com.tabstation.pip.scstream", qos: .userInteractive)
    private let lock = NSLock()
    private var stream: SCStream?
    private var scWindow: SCWindow?
    private var isStopped = false

    var onFrame: ((CGImage) -> Void)?
    var onStateChange: ((Bool) -> Void)?

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func start(scWindow: SCWindow, pixelSize: CGSize) async {
        let shouldStart = withLock { () -> Bool in
            guard !isStopped else { return false }
            self.scWindow = scWindow
            return true
        }
        guard shouldStart else { return }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = makeConfiguration(windowFrame: scWindow.frame, targetSize: pixelSize)
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)

        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            try await newStream.startCapture()

            let cancelled = withLock { () -> Bool in
                if isStopped {
                    return true
                }
                self.stream = newStream
                return false
            }

            if cancelled {
                try? await newStream.stopCapture()
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.onStateChange?(true)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onStateChange?(false)
            }
        }
    }

    func updateSize(pixelSize: CGSize) {
        let (activeStream, win) = withLock { (isStopped ? nil : stream, scWindow) }
        guard let activeStream, let win else { return }
        let config = makeConfiguration(windowFrame: win.frame, targetSize: pixelSize)
        Task {
            try? await activeStream.updateConfiguration(config)
        }
    }

    func stop() {
        let activeStream = withLock { () -> SCStream? in
            isStopped = true
            let current = stream
            stream = nil
            scWindow = nil
            onFrame = nil
            onStateChange = nil
            return current
        }

        if let activeStream {
            activeStream.stopCapture { _ in }
        }
    }

    private func makeConfiguration(windowFrame: CGRect, targetSize: CGSize) -> SCStreamConfiguration {
        let srcW = max(1, windowFrame.width)
        let srcH = max(1, windowFrame.height)
        let scale = min(max(64, targetSize.width) / srcW, max(64, targetSize.height) / srcH, 2.0)

        var width = max(64, Int((srcW * scale).rounded()))
        var height = max(64, Int((srcH * scale).rounded()))
        // Even dimensions keep video pixel converters happy on all GPUs.
        if width % 2 != 0 { width += 1 }
        if height % 2 != 0 { height += 1 }

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.showsCursor = false
        config.scalesToFit = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return config
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen else { return }
        guard withLock({ !isStopped }) else { return }

        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var cgImage: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage) == noErr,
              let image = cgImage else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let callback = self.withLock { self.isStopped ? nil : self.onFrame }
            callback?(image)
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let stopped = self.withLock { () -> Bool in
                self.stream = nil
                return self.isStopped
            }
            if !stopped {
                self.onStateChange?(false)
            }
        }
    }
}

/// Content view for a ScreenCaptureKit live Picture-in-Picture window.
final class PinnedWindowContentView: NSView {

    let windowInfo: WindowInfo

    private let surfaceView = GlassSurfaceView(cornerRadius: 12)
    private let titleBar = NSView()
    private let titleSeparator = NSView()
    private let liveDot = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    private let ghostButton = NSButton()
    private let opacityButton = NSButton()
    private let focusButton = NSButton()
    private let closeButton = NSButton()

    private let mirrorHost = NSView()
    private let fallbackIconView = NSImageView()
    private let liveStream = LiveMirrorStream()
    private var appearanceObserver: NSObjectProtocol?

    var onClose: (() -> Void)?
    var onGhostToggled: ((Bool) -> Void)?

    private(set) var isGhostMode = false

    private let opacityLevels: [CGFloat] = [1.0, 0.80, 0.55, 0.35]
    private var currentOpacityIndex = 0

    init(window: WindowInfo) {
        self.windowInfo = window
        super.init(frame: .zero)
        buildUI()
        applyAppearance()
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .tabStationAppearanceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearance()
        }
        startLiveStream()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildUI() {
        wantsLayer = true
        surfaceView.autoresizingMask = [.width, .height]
        addSubview(surfaceView)

        let container = surfaceView.contentContainer

        titleBar.wantsLayer = true
        titleSeparator.wantsLayer = true

        liveDot.wantsLayer = true
        liveDot.layer?.cornerRadius = 3
        liveDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        liveDot.toolTip = L10n.t("Connecting ScreenCaptureKit stream…", "正在连接 ScreenCaptureKit 实时画面流…")
        titleBar.addSubview(liveDot)

        iconView.image = NSRunningApplication(processIdentifier: windowInfo.pid)?.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleBar.addSubview(iconView)

        let initialTitle = windowInfo.title.isEmpty ? windowInfo.ownerName : windowInfo.title
        titleLabel.stringValue = initialTitle
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleBar.addSubview(titleLabel)

        ghostButton.isBordered = false
        ghostButton.bezelStyle = .regularSquare
        ghostButton.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: L10n.t("Ghost Mode (Click-Through)", "幽灵模式（鼠标穿透）"))
        ghostButton.toolTip = L10n.t(
            "Ghost Mode (Click-Through)\nLet clicks pass straight through this PiP window",
            "幽灵模式（鼠标穿透）\n让鼠标点击直接穿透此画中画悬浮窗"
        )
        ghostButton.target = self
        ghostButton.action = #selector(toggleGhostMode)
        titleBar.addSubview(ghostButton)

        opacityButton.isBordered = false
        opacityButton.bezelStyle = .regularSquare
        opacityButton.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: L10n.t("Adjust Opacity", "调节不透明度"))
        opacityButton.toolTip = L10n.t(
            "Opacity: 100%\nClick to cycle (100% -> 80% -> 55% -> 35%)\nOr scroll wheel over title bar",
            "不透明度：100%\n点击循环切换（100% -> 80% -> 55% -> 35%）\n或在标题栏上滑动滚轮"
        )
        opacityButton.target = self
        opacityButton.action = #selector(cycleOpacity)
        titleBar.addSubview(opacityButton)

        focusButton.isBordered = false
        focusButton.bezelStyle = .regularSquare
        focusButton.image = NSImage(systemSymbolName: "arrow.up.forward.app.fill", accessibilityDescription: L10n.t("Focus Original Window", "聚焦原窗口"))
        focusButton.toolTip = L10n.t(
            "Focus Original Window (Double-click anywhere)",
            "跳转到原窗口（双击画面任意位置）"
        )
        focusButton.target = self
        focusButton.action = #selector(focusOriginalWindow)
        titleBar.addSubview(focusButton)

        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L10n.t("Close PiP", "关闭画中画"))
        closeButton.toolTip = L10n.t("Close PiP", "关闭画中画")
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        titleBar.addSubview(closeButton)

        // Video frame canvas backed directly by CALayer.contents for zero-copy Retina updates.
        mirrorHost.wantsLayer = true
        mirrorHost.layer?.contentsGravity = .resizeAspect
        mirrorHost.layer?.masksToBounds = true
        mirrorHost.layer?.cornerRadius = 8
        mirrorHost.layer?.cornerCurve = .continuous

        fallbackIconView.image = NSRunningApplication(processIdentifier: windowInfo.pid)?.icon
        fallbackIconView.imageScaling = .scaleProportionallyUpOrDown
        mirrorHost.addSubview(fallbackIconView)

        container.addSubview(mirrorHost)
        container.addSubview(titleSeparator)
        container.addSubview(titleBar)
    }

    override func layout() {
        super.layout()
        surfaceView.frame = bounds
        let b = bounds
        let barHeight: CGFloat = 26

        titleBar.frame = NSRect(x: 0, y: b.height - barHeight, width: b.width, height: barHeight)
        titleSeparator.frame = NSRect(x: 0, y: b.height - barHeight, width: b.width, height: 0.5)

        liveDot.frame = NSRect(x: 8, y: 10, width: 6, height: 6)
        iconView.frame = NSRect(x: 18, y: 5, width: 16, height: 16)

        let btnSize: CGFloat = 18
        let btnY: CGFloat = 4
        let spacing: CGFloat = 4

        closeButton.frame = NSRect(x: max(0, b.width - 24), y: btnY, width: btnSize, height: btnSize)
        focusButton.frame = NSRect(x: max(0, closeButton.frame.minX - btnSize - spacing), y: btnY, width: btnSize, height: btnSize)
        opacityButton.frame = NSRect(x: max(0, focusButton.frame.minX - btnSize - spacing), y: btnY, width: btnSize, height: btnSize)
        ghostButton.frame = NSRect(x: max(0, opacityButton.frame.minX - btnSize - spacing), y: btnY, width: btnSize, height: btnSize)

        let titleStartX: CGFloat = 39
        let rightEdgeOfTitle = ghostButton.frame.minX - 6
        titleLabel.frame = NSRect(x: titleStartX, y: 5, width: max(0, rightEdgeOfTitle - titleStartX), height: 16)

        let contentFrame = NSRect(x: 4, y: 4, width: max(0, b.width - 8), height: max(0, b.height - barHeight - 6))
        mirrorHost.frame = contentFrame
        let iconSize = min(48, min(contentFrame.width, contentFrame.height) * 0.35)
        fallbackIconView.frame = NSRect(
            x: (contentFrame.width - iconSize) / 2,
            y: (contentFrame.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
    }

    func applyAppearance() {
        let resolved = Theme.resolvedAppearance(for: self)
        appearance = resolved
        surfaceView.applyAppearance()
        titleSeparator.layer?.backgroundColor = Theme.cellBorder.resolvedCGColor(for: resolved)
        mirrorHost.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).resolvedCGColor(for: resolved)

        let tint = NSColor.labelColor.withAlphaComponent(0.78)
        ghostButton.contentTintColor = isGhostMode ? NSColor.systemTeal : tint
        opacityButton.contentTintColor = tint
        focusButton.contentTintColor = tint
        closeButton.contentTintColor = tint
    }

    // MARK: - ScreenCaptureKit Live Stream

    private func currentStreamPixelSize() -> CGSize {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let contentW = max(360, bounds.width)
        let contentH = max(220, bounds.height)
        return CGSize(width: contentW * scale, height: contentH * scale)
    }

    private func startLiveStream() {
        let targetInfo = windowInfo
        let initialSize = currentStreamPixelSize()

        liveStream.onFrame = { [weak self] image in
            self?.renderFrame(image)
        }
        liveStream.onStateChange = { [weak self] isLive in
            guard let self else { return }
            self.liveDot.layer?.backgroundColor = (isLive ? NSColor.systemGreen : NSColor.systemOrange).cgColor
            self.liveDot.toolTip = isLive
                ? L10n.t("ScreenCaptureKit Live Mirror (30fps max)", "ScreenCaptureKit 实时镜像（最高 30fps）")
                : L10n.t("Stream unavailable (showing snapshot)", "实时流不可用（当前显示快照）")
        }

        Task { [weak self] in
            guard let self else { return }
            guard let scWindow = await ThumbnailService.shared.shareableWindow(for: targetInfo) else {
                await self.loadFallbackSnapshot(windowID: targetInfo.id, pixelSize: initialSize)
                return
            }

            // Paint a quick initial frame immediately while SCStream completes startup.
            await self.loadFallbackSnapshot(windowID: scWindow.windowID, pixelSize: initialSize)
            await self.liveStream.start(scWindow: scWindow, pixelSize: initialSize)
        }
    }

    @MainActor
    private func renderFrame(_ image: CGImage) {
        fallbackIconView.isHidden = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mirrorHost.layer?.contents = image
        CATransaction.commit()
    }

    private func loadFallbackSnapshot(windowID: CGWindowID, pixelSize: CGSize) async {
        guard let image = await ThumbnailService.shared.thumbnail(
            windowID: windowID,
            pixelSize: pixelSize,
            tier: .preview
        ) else {
            return
        }
        await MainActor.run { [weak self] in
            guard let self, self.mirrorHost.layer?.contents == nil else { return }
            self.renderFrame(image)
        }
    }

    func updateStreamSize() {
        liveStream.updateSize(pixelSize: currentStreamPixelSize())
    }

    func stopStream() {
        liveStream.stop()
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
            self.appearanceObserver = nil
        }
    }

    // MARK: - Mouse Interactions

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if !titleBar.frame.contains(loc), event.clickCount >= 2 {
            focusOriginalWindow()
            return
        }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if titleBar.frame.contains(loc), let win = window {
            let delta = event.scrollingDeltaY * 0.02
            let newAlpha = min(1.0, max(0.25, win.alphaValue + delta))
            win.alphaValue = newAlpha
            opacityButton.toolTip = L10n.t(
                "Opacity: \(Int(newAlpha * 100))%\nClick to cycle\nOr scroll wheel over title bar",
                "不透明度：\(Int(newAlpha * 100))%\n点击循环切换\n或在标题栏上滑动滚轮"
            )
            return
        }
        super.scrollWheel(with: event)
    }

    // MARK: - Ghost Mode & Opacity

    @objc private func toggleGhostMode() {
        guard let win = window else { return }
        isGhostMode.toggle()
        win.ignoresMouseEvents = isGhostMode
        ghostButton.contentTintColor = isGhostMode
            ? NSColor.systemTeal
            : NSColor.labelColor.withAlphaComponent(0.78)
        if isGhostMode {
            win.alphaValue = min(win.alphaValue, 0.65)
        }
        onGhostToggled?(isGhostMode)
    }

    func setGhostMode(_ active: Bool) {
        guard let win = window else { return }
        isGhostMode = active
        win.ignoresMouseEvents = active
        ghostButton.contentTintColor = active
            ? NSColor.systemTeal
            : NSColor.labelColor.withAlphaComponent(0.78)
        if active {
            win.alphaValue = min(win.alphaValue, 0.65)
        }
    }

    @objc private func cycleOpacity() {
        currentOpacityIndex = (currentOpacityIndex + 1) % opacityLevels.count
        let alpha = opacityLevels[currentOpacityIndex]
        window?.alphaValue = alpha
        opacityButton.toolTip = L10n.t(
            "Opacity: \(Int(alpha * 100))%\nClick to cycle\nOr scroll wheel over title bar",
            "不透明度：\(Int(alpha * 100))%\n点击循环切换\n或在标题栏上滑动滚轮"
        )
    }

    @objc private func focusOriginalWindow() {
        WindowActivator.activate(windowInfo)
    }

    @objc private func closeClicked() {
        stopStream()
        onClose?()
    }

    deinit {
        stopStream()
    }
}

/// Floating always-on-top Picture-in-Picture window backed by live ScreenCaptureKit streaming.
final class PinnedWindowPanel: NSPanel, NSWindowDelegate {

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
        let height: CGFloat = (width / aspect).rounded() + 30

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
        delegate = self
        contentView = pinContentView
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        pinContentView.updateStreamSize()
    }

    override func close() {
        pinContentView.stopStream()
        super.close()
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
            return (false, L10n.t("Unpinned \(window.ownerName)", "已取消置顶 \(window.ownerName)"))
        }

        let panel = PinnedWindowPanel(window: window, on: screen)
        panel.onClose = { [weak self] in
            self?.pinnedPanels.removeValue(forKey: window.id)
        }
        panel.orderFrontRegardless()
        pinnedPanels[window.id] = panel
        return (true, L10n.t("Pinned \(window.ownerName) to Live PiP", "已将 \(window.ownerName) 置顶为实时画中画"))
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
