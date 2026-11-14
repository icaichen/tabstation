import AppKit

/// Circular color swatch button for picking highlight/accent presets in Settings.
private final class AccentSwatchButton: NSButton {
    let choice: AccentColorChoice
    var isSelectedSwatch: Bool = false {
        didSet { needsDisplay = true }
    }

    init(choice: AccentColorChoice, target: AnyObject?, action: Selector?) {
        self.choice = choice
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        toolTip = choice.title
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var swatchColor: NSColor {
        switch choice {
        case .system: return NSColor.controlAccentColor
        case .graphite: return NSColor.secondaryLabelColor
        case .blue: return NSColor.systemBlue
        case .purple: return NSColor.systemPurple
        case .pink: return NSColor.systemPink
        case .orange: return NSColor.systemOrange
        case .green: return NSColor.systemGreen
        case .custom: return AppearancePreferences.customAccentColor
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let outer = bounds.insetBy(dx: 1.5, dy: 1.5)
        if isSelectedSwatch {
            NSColor.labelColor.withAlphaComponent(0.75).setStroke()
            let ring = NSBezierPath(ovalIn: outer)
            ring.lineWidth = 1.5
            ring.stroke()
        }

        let fillRect = bounds.insetBy(dx: 4, dy: 4)
        let fill = NSBezierPath(ovalIn: fillRect)
        swatchColor.setFill()
        fill.fill()

        NSColor.black.withAlphaComponent(0.15).setStroke()
        fill.lineWidth = 0.5
        fill.stroke()
    }
}

/// One "what it does + which key does it" row. Every switcher action is a row,
/// and the shortcut it uses is edited right there.
final class ShortcutRowView: NSView {

    enum MessageKind {
        case error
        case warning
    }

    let role: ShortcutRole
    var onChange: ((Shortcut) -> Void)?
    var onScopeChange: ((WindowScope) -> Void)?

    private let recorder = ShortcutRecorderView()
    private let scopePopup = NSPopUpButton()
    private let resetButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")

    init(role: ShortcutRole) {
        self.role = role
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        titleLabel.stringValue = role.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        subtitleLabel.stringValue = role.subtitle
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2

        scopePopup.removeAllItems()
        scopePopup.addItems(withTitles: WindowScope.allCases.map(\.title))
        scopePopup.controlSize = .small
        scopePopup.font = .systemFont(ofSize: 11)
        let currentScope = ShortcutScopeStore.load(role)
        scopePopup.selectItem(at: WindowScope.allCases.firstIndex(of: currentScope) ?? 0)
        scopePopup.target = self
        scopePopup.action = #selector(scopeSelected)

        messageLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.isHidden = true

        recorder.role = role
        recorder.othersProvider = { ShortcutStore.loadAll().filter { $0.key != role } }
        recorder.onChange = { [weak self] shortcut in self?.handleChange(shortcut) }
        recorder.onInvalid = { [weak self] reason in self?.showMessage(reason, kind: .error) }

        resetButton.isBordered = false
        resetButton.bezelStyle = .regularSquare
        resetButton.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: L10n.t("Reset to default", "恢复默认"))
        resetButton.toolTip = L10n.t("Reset to default (\(role.defaultShortcut.displayString))", "恢复默认（\(role.defaultShortcut.displayString)）")
        resetButton.contentTintColor = .secondaryLabelColor
        resetButton.target = self
        resetButton.action = #selector(resetToDefault)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.widthAnchor.constraint(equalToConstant: 18).isActive = true
        resetButton.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let titleRow = NSStackView(views: [titleLabel, spacer, scopePopup, recorder, resetButton])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        let stack = NSStackView(views: [titleRow, subtitleLabel, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            messageLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setShortcut(_ shortcut: Shortcut, scope: WindowScope) {
        recorder.setShortcut(shortcut)
        scopePopup.selectItem(at: WindowScope.allCases.firstIndex(of: scope) ?? 0)
        refreshMessage(for: shortcut)
    }

    private func refreshMessage(for shortcut: Shortcut) {
        if let warning = ShortcutValidator.warning(for: shortcut) {
            showMessage(warning, kind: .warning)
        } else {
            showMessage(nil, kind: .error)
        }
    }

    @objc private func scopeSelected(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        let scope: WindowScope = (idx == 1) ? .activeApp : .allApps
        ShortcutScopeStore.save(scope, for: role)
        onScopeChange?(scope)
    }

    @objc private func resetToDefault() {
        handleChange(role.defaultShortcut)
        let defaultScope: WindowScope = (role == .sameApp) ? .activeApp : .allApps
        ShortcutScopeStore.save(defaultScope, for: role)
        scopePopup.selectItem(at: WindowScope.allCases.firstIndex(of: defaultScope) ?? 0)
        onScopeChange?(defaultScope)
    }

    private func handleChange(_ shortcut: Shortcut) {
        if let reason = ShortcutValidator.validate(shortcut, for: role) {
            showMessage(reason, kind: .error)
            NSSound.beep()
            return
        }
        ShortcutStore.save(shortcut, for: role)
        recorder.setShortcut(shortcut)
        refreshMessage(for: shortcut)
        onChange?(shortcut)
    }

    private func showMessage(_ text: String?, kind: MessageKind) {
        guard let text else {
            messageLabel.isHidden = true
            messageLabel.stringValue = ""
            return
        }
        messageLabel.isHidden = false
        messageLabel.stringValue = text
        messageLabel.textColor = kind == .error ? .systemRed : .systemOrange
        needsLayout = true
    }
}

private final class FlippedTabDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Tabbed Preferences window: Appearance, Features, Shortcuts, and General settings.
/// Changes apply live — no relaunch required.
final class PreferencesWindowController: NSWindowController {

    var onShortcutChange: ((ShortcutRole, Shortcut) -> Void)?
    var onScopeChange: ((ShortcutRole, WindowScope) -> Void)?
    var onPrimaryChange: ((Shortcut) -> Void)?
    var onGeneralChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?

    private var rows: [ShortcutRole: ShortcutRowView] = [:]
    private var previousShortcuts: [ShortcutRole: Shortcut] = [:]
    private let legendLabel = NSTextField(labelWithString: "")

    private let tabSwitcher = NSSegmentedControl()
    private let tabView = NSTabView()

    // Appearance controls
    private let displayStyleControl = NSSegmentedControl()
    private let thumbnailSizeControl = NSSegmentedControl()
    private let autoAdjustSizeSwitch = NSSwitch()
    private let themeControl = NSSegmentedControl()
    private let backgroundStyleControl = NSSegmentedControl()
    private let opacitySlider = NSSlider(value: 0.85, minValue: 0.30, maxValue: 1.0, target: nil, action: nil)
    private let opacityValueLabel = NSTextField(labelWithString: "85%")
    private var swatchButtons: [AccentSwatchButton] = []
    private let customColorWell = NSColorWell()
    private let showFooterHintsSwitch = NSSwitch()

    // Feature controls
    private let arrowKeySnappingSwitch = NSSwitch()
    private let autoPreviewOnHoldSwitch = NSSwitch()
    private let spaceQuickLookSwitch = NSSwitch()
    private let hoverActionPillsSwitch = NSSwitch()
    private let displayMoveShortcutSwitch = NSSwitch()
    private let pinShortcutSwitch = NSSwitch()
    private let browserTabsShortcutSwitch = NSSwitch()
    private let includeBrowserTabsSwitch = NSSwitch()

    // General controls
    private let overrideCommandTabSwitch = NSSwitch()
    private let followActiveDisplaySwitch = NSSwitch()
    private let showAllSpacesSwitch = NSSwitch()
    private let showMinimizedSwitch = NSSwitch()
    private let launchAtLoginSwitch = NSSwitch()
    private let languageControl = NSSegmentedControl()
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let screenRecordingStatusLabel = NSTextField(labelWithString: "")
    private let automationStatusLabel = NSTextField(labelWithString: "")

    private let resetButton = NSButton(title: L10n.t("Restore Defaults", "恢复默认设置"), target: nil, action: nil)
    private let doneButton = NSButton(title: L10n.t("Done", "完成"), target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("AltDeck Settings", "AltDeck 设置")
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildContent()
        reload()
        window.initialFirstResponder = doneButton
        window.center()
    }

    func show() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI

    private func buildContent() {
        guard let content = window?.contentView else { return }

        tabSwitcher.segmentCount = 4
        applyLocalizedChrome()
        tabSwitcher.segmentStyle = .automatic
        tabSwitcher.selectedSegment = 0
        tabSwitcher.target = self
        tabSwitcher.action = #selector(tabChanged)
        tabSwitcher.translatesAutoresizingMaskIntoConstraints = false

        tabView.tabViewType = .noTabsNoBorder
        tabView.translatesAutoresizingMaskIntoConstraints = false
        populateTabItems(selecting: 0)

        let topSeparator = makeHorizontalSeparator()
        let bottomSeparator = makeHorizontalSeparator()

        resetButton.target = self
        resetButton.action = #selector(restoreDefaults)
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .regular
        resetButton.font = .systemFont(ofSize: 12)

        doneButton.target = self
        doneButton.action = #selector(done)
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.controlSize = .regular

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [resetButton, spacer, doneButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(tabSwitcher)
        content.addSubview(topSeparator)
        content.addSubview(tabView)
        content.addSubview(bottomSeparator)
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            tabSwitcher.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            tabSwitcher.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            topSeparator.topAnchor.constraint(equalTo: tabSwitcher.bottomAnchor, constant: 12),
            topSeparator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            tabView.topAnchor.constraint(equalTo: topSeparator.bottomAnchor, constant: 8),
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabView.bottomAnchor.constraint(equalTo: bottomSeparator.topAnchor, constant: -10),

            bottomSeparator.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            bottomSeparator.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            bottomSeparator.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),

            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    private func applyLocalizedChrome() {
        window?.title = L10n.t("AltDeck Settings", "AltDeck 设置")
        tabSwitcher.setLabel(L10n.t("Appearance", "外观"), forSegment: 0)
        tabSwitcher.setLabel(L10n.t("Features", "功能"), forSegment: 1)
        tabSwitcher.setLabel(L10n.t("Shortcuts", "快捷键"), forSegment: 2)
        tabSwitcher.setLabel(L10n.t("General", "通用"), forSegment: 3)
        resetButton.title = L10n.t("Restore Defaults", "恢复默认设置")
        doneButton.title = L10n.t("Done", "完成")
    }

    private func populateTabItems(selecting segment: Int) {
        while let first = tabView.tabViewItems.first {
            tabView.removeTabViewItem(first)
        }
        let specs: [(String, NSView)] = [
            ("appearance", wrapScrollableTab(buildAppearanceTab())),
            ("features", wrapScrollableTab(buildFeaturesTab())),
            ("shortcuts", wrapScrollableTab(buildShortcutsTab())),
            ("general", wrapScrollableTab(buildGeneralTab())),
        ]
        for (id, view) in specs {
            let item = NSTabViewItem(identifier: id)
            item.view = view
            tabView.addTabViewItem(item)
        }
        let clamped = max(0, min(specs.count - 1, segment))
        tabSwitcher.selectedSegment = clamped
        tabView.selectTabViewItem(at: clamped)
    }

    private func rebuildLocalizedUI() {
        let currentSegment = tabSwitcher.selectedSegment
        applyLocalizedChrome()
        populateTabItems(selecting: currentSegment)
        reload()
    }

    private func wrapScrollableTab(_ innerView: NSView) -> NSView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let doc = FlippedTabDocumentView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        innerView.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(innerView)

        scroll.documentView = doc

        NSLayoutConstraint.activate([
            innerView.topAnchor.constraint(equalTo: doc.topAnchor, constant: 6),
            innerView.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -8),
            innerView.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 8),
            innerView.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -8),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return scroll
    }

    private func buildAppearanceTab() -> NSView {
        displayStyleControl.segmentCount = 3
        displayStyleControl.setLabel(L10n.t("Thumbnails & Titles", "缩略图与标题"), forSegment: 0)
        displayStyleControl.setLabel(L10n.t("Thumbnails Only", "仅缩略图"), forSegment: 1)
        displayStyleControl.setLabel(L10n.t("Icons Only", "仅图标"), forSegment: 2)
        displayStyleControl.target = self
        displayStyleControl.action = #selector(displayStyleChanged)

        thumbnailSizeControl.segmentCount = 3
        thumbnailSizeControl.setLabel(ThumbnailSize.small.title, forSegment: 0)
        thumbnailSizeControl.setLabel(ThumbnailSize.medium.title, forSegment: 1)
        thumbnailSizeControl.setLabel(ThumbnailSize.large.title, forSegment: 2)
        thumbnailSizeControl.target = self
        thumbnailSizeControl.action = #selector(thumbnailSizeChanged)

        let layoutCard = makeSectionCard(title: L10n.t("Layout & Sizing", "布局与尺寸"), rows: [
            makeLabeledRow(label: L10n.t("Mode", "显示模式"), control: displayStyleControl),
            makeLabeledRow(label: L10n.t("Tile Size", "卡片尺寸"), control: thumbnailSizeControl),
            makeSwitchRow(
                title: L10n.t("Auto-adjust size to fit open windows", "根据窗口数量自动缩放尺寸"),
                subtitle: L10n.t(
                    "Scales tiles cleanly across multiple rows when many windows are open.",
                    "当打开较多窗口时自动调整卡片大小并整洁换行。"
                ),
                toggle: autoAdjustSizeSwitch,
                action: #selector(toggleAutoAdjustSize)
            ),
        ])

        themeControl.segmentCount = 3
        for (idx, theme) in AppearanceTheme.allCases.enumerated() {
            themeControl.setLabel(theme.title, forSegment: idx)
        }
        themeControl.target = self
        themeControl.action = #selector(themeChanged)

        backgroundStyleControl.segmentCount = 3
        for (idx, bg) in BackgroundStyle.allCases.enumerated() {
            backgroundStyleControl.setLabel(bg.title, forSegment: idx)
        }
        backgroundStyleControl.target = self
        backgroundStyleControl.action = #selector(backgroundStyleChanged)

        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        opacitySlider.translatesAutoresizingMaskIntoConstraints = false
        if opacitySlider.constraints.isEmpty {
            opacitySlider.widthAnchor.constraint(equalToConstant: 230).isActive = true
        }

        opacityValueLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        opacityValueLabel.textColor = .secondaryLabelColor
        opacityValueLabel.alignment = .right
        opacityValueLabel.translatesAutoresizingMaskIntoConstraints = false
        if opacityValueLabel.constraints.isEmpty {
            opacityValueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        }

        let opacityRowControl = NSStackView(views: [opacitySlider, opacityValueLabel])
        opacityRowControl.orientation = .horizontal
        opacityRowControl.alignment = .centerY
        opacityRowControl.spacing = 8

        let surfaceCard = makeSectionCard(title: L10n.t("Liquid Glass & Surface", "液态玻璃与外观"), rows: [
            makeLabeledRow(label: L10n.t("Theme", "界面主题"), control: themeControl),
            makeLabeledRow(label: L10n.t("Surface", "背景材质"), control: backgroundStyleControl),
            makeLabeledRow(label: L10n.t("Tint Density", "着色浓度"), control: opacityRowControl),
        ])

        swatchButtons = AccentColorChoice.presets.map { choice in
            AccentSwatchButton(choice: choice, target: self, action: #selector(swatchClicked(_:)))
        }

        customColorWell.target = self
        customColorWell.action = #selector(customColorChanged(_:))
        customColorWell.toolTip = L10n.t("Custom Highlight Color", "自定义高亮色")
        customColorWell.translatesAutoresizingMaskIntoConstraints = false
        if customColorWell.constraints.isEmpty {
            customColorWell.widthAnchor.constraint(equalToConstant: 36).isActive = true
            customColorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true
        }

        var swatchViews: [NSView] = swatchButtons
        swatchViews.append(customColorWell)
        let swatchRow = NSStackView(views: swatchViews)
        swatchRow.orientation = .horizontal
        swatchRow.alignment = .centerY
        swatchRow.spacing = 6

        let highlightCard = makeSectionCard(title: L10n.t("Selection & Footer", "选中高亮与底栏"), rows: [
            makeLabeledRow(label: L10n.t("Highlight", "高亮颜色"), control: swatchRow),
            makeSwitchRow(
                title: L10n.t("Show shortcut hints in footer", "底部显示快捷键提示"),
                subtitle: L10n.t(
                    "Displays an unobtrusive bottom legend bar in thumbnail modes.",
                    "在缩略图模式下于底部显示简洁的操作按键提示栏。"
                ),
                toggle: showFooterHintsSwitch,
                action: #selector(toggleShowFooterHints)
            ),
        ])

        return makeCardStack([layoutCard, surfaceCard, highlightCard])
    }

    private func buildFeaturesTab() -> NSView {
        let previewCard = makeSectionCard(title: L10n.t("Preview & Hover Controls", "预览与悬停交互"), rows: [
            makeSwitchRow(
                title: L10n.t("Hold-to-Preview when pausing on an icon", "停留在图标上时自动预览"),
                subtitle: L10n.t(
                    "In Icons Only mode, rest briefly on an icon while holding Command/Option to peek the window.",
                    "在“仅图标”模式下，按住切换键并在图标上稍作停留即可预览窗口内容。"
                ),
                toggle: autoPreviewOnHoldSwitch,
                action: #selector(toggleAutoPreviewOnHold)
            ),
            makeSwitchRow(
                title: L10n.t("Spacebar persistent Quick Look (Space)", "空格键常驻快速预览 (Space)"),
                subtitle: L10n.t(
                    "Press Space to lock a floating window preview open as you switch.",
                    "按空格键在切换期间常驻放大查看所选窗口。"
                ),
                toggle: spaceQuickLookSwitch,
                action: #selector(toggleSpaceQuickLook)
            ),
            makeSwitchRow(
                title: L10n.t("Hover Quick-Action Pills", "悬停快捷操作按钮"),
                subtitle: L10n.t(
                    "Show left/right snap and close buttons when moving the pointer over thumbnails.",
                    "鼠标移动到缩略图上时显示左/右分屏贴靠与关闭窗口按钮。"
                ),
                toggle: hoverActionPillsSwitch,
                action: #selector(toggleHoverActionPills)
            ),
        ])

        let workspaceCard = makeSectionCard(title: L10n.t("Window Tiling & Navigation", "窗口分屏与跨屏"), rows: [
            makeSwitchRow(
                title: L10n.t("Arrow-Key Window Snapping (← / → / ↑ / ↓ & C)", "方向键窗口贴靠 (← / → / ↑ / ↓ 与 C)"),
                subtitle: L10n.t(
                    "Snap the selected window to screen halves or maximize. Turn off to rotate icons with arrow keys.",
                    "将选中窗口贴靠至半屏、三分之一或最大化；关闭则仅用方向键移动选中。"
                ),
                toggle: arrowKeySnappingSwitch,
                action: #selector(toggleArrowKeySnapping)
            ),
            makeSwitchRow(
                title: L10n.t("Move Window Across Displays (D)", "跨显示器移动窗口 (D)"),
                subtitle: L10n.t(
                    "Send the selected window directly to your next connected monitor.",
                    "按 D 直接将当前选中的窗口发送到下一台外接显示器。"
                ),
                toggle: displayMoveShortcutSwitch,
                action: #selector(toggleDisplayMoveShortcut)
            ),
            makeSwitchRow(
                title: L10n.t("Float Window on Top / PiP (P)", "窗口置顶 / 实时画中画 (P)"),
                subtitle: L10n.t(
                    "Pin any window into a live ScreenCaptureKit Picture-in-Picture overlay with Ghost Mode.",
                    "将任意窗口置顶为支持鼠标穿透的 ScreenCaptureKit 实时画中画悬浮窗。"
                ),
                toggle: pinShortcutSwitch,
                action: #selector(togglePinShortcut)
            ),
        ])

        let browserCard = makeSectionCard(title: L10n.t("Browser & App Sources", "浏览器与窗口来源"), rows: [
            makeSwitchRow(
                title: L10n.t("Browser Tab Filter Shortcut (S)", "浏览器标签页过滤快捷键 (S)"),
                subtitle: L10n.t(
                    "Press S in the switcher to jump to open tabs from Chrome, Safari, Arc, Edge, and Brave.",
                    "打开切换器时按 S 即可一键切换至 Chrome、Safari、Arc、Edge 与 Brave 标签页。"
                ),
                toggle: browserTabsShortcutSwitch,
                action: #selector(toggleBrowserTabsShortcut)
            ),
            makeSwitchRow(
                title: L10n.t("Show Browser Tabs in Main List by Default", "默认在主列表中混排浏览器标签页"),
                subtitle: L10n.t(
                    "Always mix open browser tabs into the main switcher strip instead of only showing them on S.",
                    "开启后默认将标签页混入主窗口列表，而非仅在按下 S 后显示。"
                ),
                toggle: includeBrowserTabsSwitch,
                action: #selector(toggleIncludeBrowserTabs)
            ),
        ])

        return makeCardStack([previewCard, workspaceCard, browserCard])
    }

    private func buildShortcutsTab() -> NSView {
        rows.removeAll()
        let intro = NSTextField(wrappingLabelWithString: L10n.t(
            "Hold a shortcut, tap its key to cycle windows, then release to switch.",
            "按住快捷键并通过按键循环选择窗口，松开后即切换至目标窗口。"
        ))
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        intro.maximumNumberOfLines = 2

        var stackViews: [NSView] = [intro]
        for role in ShortcutRole.allCases {
            previousShortcuts[role] = ShortcutStore.load(role)
            let row = ShortcutRowView(role: role)
            row.onScopeChange = { [weak self] scope in
                self?.onScopeChange?(role, scope)
            }
            row.onChange = { [weak self] shortcut in
                guard let self else { return }
                for otherRole in ShortcutRole.allCases where otherRole != role {
                    let otherShortcut = ShortcutStore.load(otherRole)
                    if otherShortcut.normalized == shortcut.normalized && otherShortcut.keyCode == shortcut.keyCode {
                        let oldShortcut = self.previousShortcuts[role] ?? role.defaultShortcut
                        ShortcutStore.save(oldShortcut, for: otherRole)
                        self.previousShortcuts[otherRole] = oldShortcut
                        let otherScope = ShortcutScopeStore.load(otherRole)
                        self.rows[otherRole]?.setShortcut(oldShortcut, scope: otherScope)
                        self.onShortcutChange?(otherRole, oldShortcut)
                        if otherRole == .primary {
                            self.onPrimaryChange?(oldShortcut)
                        }
                        break
                    }
                }

                self.previousShortcuts[role] = shortcut
                self.refreshLegend()
                self.onShortcutChange?(role, shortcut)
                if role == .primary {
                    self.onPrimaryChange?(shortcut)
                }
            }
            rows[role] = row
            stackViews.append(row)
        }

        legendLabel.font = .systemFont(ofSize: 11.5)
        legendLabel.textColor = .secondaryLabelColor
        legendLabel.alignment = .center
        legendLabel.lineBreakMode = .byWordWrapping
        legendLabel.maximumNumberOfLines = 2
        stackViews.append(legendLabel)

        return makeCardStack(stackViews, spacing: 12)
    }

    private func buildGeneralTab() -> NSView {
        languageControl.segmentCount = AppLanguage.allCases.count
        for (idx, lang) in AppLanguage.allCases.enumerated() {
            languageControl.setLabel(lang.title, forSegment: idx)
        }
        languageControl.target = self
        languageControl.action = #selector(languageChanged)

        let behaviorCard = makeSectionCard(title: L10n.t("Behavior & System Integration", "行为与系统集成"), rows: [
            makeLabeledRow(label: L10n.t("Language", "界面语言"), control: languageControl),
            makeSwitchRow(
                title: L10n.t("Override ⌘Tab", "接管系统 ⌘Tab"),
                subtitle: L10n.t(
                    "Replace the built-in macOS application switcher with AltDeck.",
                    "用 AltDeck 替换 macOS 默认的应用切换器。"
                ),
                toggle: overrideCommandTabSwitch,
                action: #selector(toggleOverrideCommandTab)
            ),
            makeSwitchRow(
                title: L10n.t("Follow Active Display", "跟随当前显示器"),
                subtitle: L10n.t(
                    "Bring the switched window onto the monitor under your cursor if needed.",
                    "必要时将切换的目标窗口移动到鼠标所在的显示器。"
                ),
                toggle: followActiveDisplaySwitch,
                action: #selector(toggleFollowActiveDisplay)
            ),
            makeSwitchRow(
                title: L10n.t("Show Windows from All Spaces", "显示所有调度空间中的窗口"),
                subtitle: L10n.t(
                    "Include windows from other desktops and full-screen Spaces.",
                    "包含其他桌面空间以及全屏应用窗口。"
                ),
                toggle: showAllSpacesSwitch,
                action: #selector(toggleShowAllSpaces)
            ),
            makeSwitchRow(
                title: L10n.t("Include Minimized Windows", "包含已最小化的窗口"),
                subtitle: L10n.t(
                    "Keep Dock-minimized windows selectable and auto-restore on switch.",
                    "保持最小化到程序坞的窗口可选，切换时自动还原显示。"
                ),
                toggle: showMinimizedSwitch,
                action: #selector(toggleShowMinimized)
            ),
            makeSwitchRow(
                title: L10n.t("Launch AltDeck at Login", "开机自动启动 AltDeck"),
                subtitle: L10n.t(
                    "Start automatically in the background whenever you log in.",
                    "每次登录系统时在后台自动启动。"
                ),
                toggle: launchAtLoginSwitch,
                action: #selector(toggleLaunchAtLogin)
            ),
        ])

        let permCard = makeSectionCard(title: L10n.t("macOS Permissions", "macOS 系统权限"), rows: [
            makePermissionRow(
                title: L10n.t("Accessibility", "辅助功能"),
                subtitle: L10n.t(
                    "Required for global hotkeys and raising specific app windows.",
                    "用于监听全局快捷键并唤醒、置前特定窗口。"
                ),
                statusLabel: accessibilityStatusLabel,
                action: #selector(openAccessibilityPane)
            ),
            makePermissionRow(
                title: L10n.t("Screen Recording", "屏幕录制"),
                subtitle: L10n.t(
                    "Required for live window previews and reading offscreen window titles.",
                    "用于捕获实时窗口缩略图预览并读取窗口标题。"
                ),
                statusLabel: screenRecordingStatusLabel,
                action: #selector(openScreenRecordingPane)
            ),
            makePermissionRow(
                title: L10n.t("Automation (Browsers)", "自动化控制（浏览器）"),
                subtitle: L10n.t(
                    "Required for listing and switching Chrome, Safari, Edge, Brave, and Arc tabs.",
                    "用于读取并一键跳转 Chrome、Safari、Edge、Brave、Arc 打开的标签页。"
                ),
                statusLabel: automationStatusLabel,
                action: #selector(openAutomationPane)
            ),
        ])

        return makeCardStack([behaviorCard, permCard])
    }

    private func makeCardStack(_ views: [NSView], spacing: CGFloat = 12) -> NSView {
        let container = NSView()
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        var constraints: [NSLayoutConstraint] = [
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ]
        for child in views {
            constraints.append(child.widthAnchor.constraint(equalTo: stack.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }

    private func makeSectionCard(title: String, rows: [NSView]) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 11
        box.layer?.cornerCurve = .continuous
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: title.uppercased())
        header.font = .systemFont(ofSize: 10.5, weight: .semibold)
        header.textColor = .secondaryLabelColor

        var allViews: [NSView] = [header]
        for (idx, row) in rows.enumerated() {
            if idx > 0 {
                let divider = makeHorizontalSeparator()
                allViews.append(divider)
            }
            allViews.append(row)
        }

        let stack = NSStackView(views: allViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        var constraints: [NSLayoutConstraint] = [
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
        ]
        for view in allViews where view !== header {
            constraints.append(view.widthAnchor.constraint(equalTo: stack.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return box
    }

    private func makeLabeledRow(label: String, control: NSView) -> NSView {
        let titleField = NSTextField(labelWithString: label)
        titleField.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleField.textColor = .labelColor
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.widthAnchor.constraint(equalToConstant: 92).isActive = true

        let row = NSStackView(views: [titleField, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeSwitchRow(title: String, subtitle: String, toggle: NSSwitch, action: Selector) -> NSView {
        toggle.controlSize = .small
        toggle.target = self
        toggle.action = action
        toggle.setContentHuggingPriority(.required, for: .horizontal)

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleField.textColor = .labelColor

        let subtitleField = NSTextField(wrappingLabelWithString: subtitle)
        subtitleField.font = .systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.maximumNumberOfLines = 2

        let textStack = NSStackView(views: [titleField, subtitleField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [textStack, toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func makePermissionRow(
        title: String,
        subtitle: String,
        statusLabel: NSTextField,
        action: Selector
    ) -> NSView {
        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleField.textColor = .labelColor

        let subtitleField = NSTextField(wrappingLabelWithString: subtitle)
        subtitleField.font = .systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.maximumNumberOfLines = 2

        let textStack = NSStackView(views: [titleField, subtitleField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        statusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)

        let openBtn = NSButton(title: L10n.t("System Settings…", "打开系统设置…"), target: self, action: action)
        openBtn.bezelStyle = .rounded
        openBtn.controlSize = .small
        openBtn.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [textStack, statusLabel, openBtn])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeHorizontalSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        return separator
    }

    // MARK: - State

    private func reload() {
        for role in ShortcutRole.allCases {
            let s = ShortcutStore.load(role)
            let scope = ShortcutScopeStore.load(role)
            previousShortcuts[role] = s
            rows[role]?.setShortcut(s, scope: scope)
        }
        overrideCommandTabSwitch.state = UserDefaults.standard.bool(forKey: "TabStation.overrideCommandTab") ? .on : .off
        followActiveDisplaySwitch.state = GeneralPreferences.followActiveDisplay ? .on : .off
        let allSpaces = UserDefaults.standard.object(forKey: "TabStation.showAllSpaces") as? Bool ?? true
        showAllSpacesSwitch.state = allSpaces ? .on : .off
        showMinimizedSwitch.state = UserDefaults.standard.bool(forKey: "TabStation.showMinimized") ? .on : .off
        includeBrowserTabsSwitch.state = FeaturePreferences.includeBrowserTabsByDefault ? .on : .off
        launchAtLoginSwitch.state = LaunchAtLogin.isEnabled ? .on : .off
        if let langIdx = AppLanguage.allCases.firstIndex(of: AppLanguage.current) {
            languageControl.selectedSegment = langIdx
        }

        arrowKeySnappingSwitch.state = FeaturePreferences.arrowKeySnappingEnabled ? .on : .off
        autoPreviewOnHoldSwitch.state = AppearancePreferences.autoPreviewOnHold ? .on : .off
        spaceQuickLookSwitch.state = FeaturePreferences.spaceQuickLookEnabled ? .on : .off
        hoverActionPillsSwitch.state = FeaturePreferences.hoverActionPillsEnabled ? .on : .off
        displayMoveShortcutSwitch.state = FeaturePreferences.displayMoveShortcutEnabled ? .on : .off
        pinShortcutSwitch.state = FeaturePreferences.pinShortcutEnabled ? .on : .off
        browserTabsShortcutSwitch.state = FeaturePreferences.browserTabsShortcutEnabled ? .on : .off

        switch DisplayStyle.current {
        case .full: displayStyleControl.selectedSegment = 0
        case .thumbnailsOnly: displayStyleControl.selectedSegment = 1
        case .iconsOnly: displayStyleControl.selectedSegment = 2
        }

        switch ThumbnailSize.current {
        case .small: thumbnailSizeControl.selectedSegment = 0
        case .medium: thumbnailSizeControl.selectedSegment = 1
        case .large: thumbnailSizeControl.selectedSegment = 2
        }

        autoAdjustSizeSwitch.state = AppearancePreferences.autoAdjustSize ? .on : .off
        showFooterHintsSwitch.state = AppearancePreferences.showFooterHints ? .on : .off

        if let themeIdx = AppearanceTheme.allCases.firstIndex(of: AppearancePreferences.theme) {
            themeControl.selectedSegment = themeIdx
        }
        if let bgIdx = BackgroundStyle.allCases.firstIndex(of: AppearancePreferences.backgroundStyle) {
            backgroundStyleControl.selectedSegment = bgIdx
        }

        let opacity = AppearancePreferences.panelOpacity
        opacitySlider.doubleValue = opacity
        opacityValueLabel.stringValue = "\(Int((opacity * 100).rounded()))%"

        let activeChoice = AppearancePreferences.accentColorChoice
        for btn in swatchButtons {
            btn.isSelectedSwatch = (btn.choice == activeChoice)
        }
        customColorWell.color = AppearancePreferences.customAccentColor

        let axOK = Permissions.accessibilityGranted
        accessibilityStatusLabel.stringValue = axOK ? L10n.t("● Granted", "● 已授权") : L10n.t("● Needed", "● 需授权")
        accessibilityStatusLabel.textColor = axOK ? .systemGreen : .systemOrange

        let srOK = Permissions.screenRecordingGranted
        screenRecordingStatusLabel.stringValue = srOK ? L10n.t("● Granted", "● 已授权") : L10n.t("● Optional", "● 可选")
        screenRecordingStatusLabel.textColor = srOK ? .systemGreen : .secondaryLabelColor

        switch Permissions.automationStatus(forBundleIDs: BrowserTabService.shared.supportedBundleIDs) {
        case .granted:
            automationStatusLabel.stringValue = L10n.t("● Granted", "● 已授权")
            automationStatusLabel.textColor = .systemGreen
        case .promptable:
            automationStatusLabel.stringValue = L10n.t("● Pending", "● 待授权")
            automationStatusLabel.textColor = .systemOrange
        case .denied:
            automationStatusLabel.stringValue = L10n.t("● Denied", "● 已拒绝")
            automationStatusLabel.textColor = .systemRed
        case .unavailable:
            automationStatusLabel.stringValue = L10n.t("● Idle", "● 未启动")
            automationStatusLabel.textColor = .secondaryLabelColor
        }

        refreshLegend()
    }

    private func refreshLegend() {
        let all = ShortcutStore.loadAll()
        let p = all[.primary] ?? .optionTab
        let s = all[.sameApp] ?? Shortcut(modifiers: [.option], keyCode: KeyCode.grave)
        legendLabel.stringValue = L10n.t(
            "\(p.displayString) next · \(s.displayString) same app · esc cancel",
            "\(p.displayString) 下一个 · \(s.displayString) 同应用 · esc 取消"
        )
    }

    // MARK: - Actions

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        tabView.selectTabViewItem(at: sender.selectedSegment)
    }

    @objc private func languageChanged(_ sender: NSSegmentedControl) {
        let all = AppLanguage.allCases
        guard sender.selectedSegment >= 0, sender.selectedSegment < all.count else { return }
        AppLanguage.current = all[sender.selectedSegment]
        rebuildLocalizedUI()
        onAppearanceChange?()
    }

    @objc private func displayStyleChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: DisplayStyle.current = .full
        case 1: DisplayStyle.current = .thumbnailsOnly
        case 2: DisplayStyle.current = .iconsOnly
        default: break
        }
        onAppearanceChange?()
    }

    @objc private func thumbnailSizeChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: ThumbnailSize.current = .small
        case 1: ThumbnailSize.current = .medium
        case 2: ThumbnailSize.current = .large
        default: break
        }
        onAppearanceChange?()
    }

    @objc private func toggleAutoAdjustSize(_ sender: NSSwitch) {
        AppearancePreferences.autoAdjustSize = sender.state == .on
        onAppearanceChange?()
    }

    @objc private func themeChanged(_ sender: NSSegmentedControl) {
        let themes = AppearanceTheme.allCases
        guard sender.selectedSegment >= 0, sender.selectedSegment < themes.count else { return }
        AppearancePreferences.theme = themes[sender.selectedSegment]
        onAppearanceChange?()
    }

    @objc private func backgroundStyleChanged(_ sender: NSSegmentedControl) {
        let styles = BackgroundStyle.allCases
        guard sender.selectedSegment >= 0, sender.selectedSegment < styles.count else { return }
        AppearancePreferences.backgroundStyle = styles[sender.selectedSegment]
        onAppearanceChange?()
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        let value = sender.doubleValue
        opacityValueLabel.stringValue = "\(Int((value * 100).rounded()))%"
        AppearancePreferences.panelOpacity = value
        onAppearanceChange?()
    }

    @objc private func swatchClicked(_ sender: AccentSwatchButton) {
        AppearancePreferences.accentColorChoice = sender.choice
        for btn in swatchButtons {
            btn.isSelectedSwatch = (btn.choice == sender.choice)
        }
        onAppearanceChange?()
    }

    @objc private func customColorChanged(_ sender: NSColorWell) {
        AppearancePreferences.customAccentColor = sender.color
        for btn in swatchButtons {
            btn.isSelectedSwatch = false
        }
        onAppearanceChange?()
    }

    @objc private func toggleAutoPreviewOnHold(_ sender: NSSwitch) {
        AppearancePreferences.autoPreviewOnHold = sender.state == .on
        onAppearanceChange?()
    }

    @objc private func toggleShowFooterHints(_ sender: NSSwitch) {
        AppearancePreferences.showFooterHints = sender.state == .on
        onAppearanceChange?()
    }

    @objc private func toggleArrowKeySnapping(_ sender: NSSwitch) {
        FeaturePreferences.arrowKeySnappingEnabled = sender.state == .on
        onAppearanceChange?()
    }

    @objc private func toggleSpaceQuickLook(_ sender: NSSwitch) {
        FeaturePreferences.spaceQuickLookEnabled = sender.state == .on
        onAppearanceChange?()
    }

    @objc private func toggleHoverActionPills(_ sender: NSSwitch) {
        FeaturePreferences.hoverActionPillsEnabled = sender.state == .on
        onAppearanceChange?()
    }

    @objc private func toggleDisplayMoveShortcut(_ sender: NSSwitch) {
        FeaturePreferences.displayMoveShortcutEnabled = sender.state == .on
        onAppearanceChange?()
    }

    @objc private func togglePinShortcut(_ sender: NSSwitch) {
        FeaturePreferences.pinShortcutEnabled = sender.state == .on
        onAppearanceChange?()
    }

    @objc private func toggleOverrideCommandTab(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: "TabStation.overrideCommandTab")
        onGeneralChange?()
    }

    @objc private func toggleFollowActiveDisplay(_ sender: NSSwitch) {
        GeneralPreferences.followActiveDisplay = sender.state == .on
        onGeneralChange?()
    }

    @objc private func toggleShowAllSpaces(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: "TabStation.showAllSpaces")
        WindowListCache.shared.invalidateAndPrewarm()
        onGeneralChange?()
    }

    @objc private func toggleShowMinimized(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: "TabStation.showMinimized")
        onGeneralChange?()
    }

    @objc private func toggleBrowserTabsShortcut(_ sender: NSSwitch) {
        FeaturePreferences.browserTabsShortcutEnabled = sender.state == .on
        onAppearanceChange?()
    }

    @objc private func toggleIncludeBrowserTabs(_ sender: NSSwitch) {
        FeaturePreferences.includeBrowserTabsByDefault = sender.state == .on
        WindowListCache.shared.invalidateAndPrewarm()
        onGeneralChange?()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSSwitch) {
        LaunchAtLogin.setEnabled(sender.state == .on)
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func openAccessibilityPane() {
        if !Permissions.accessibilityGranted {
            Permissions.requestAccessibility()
        }
        Permissions.openAccessibilitySettings()
    }

    @objc private func openScreenRecordingPane() {
        if !Permissions.screenRecordingGranted {
            Permissions.requestScreenRecording()
        }
        Permissions.openScreenRecordingSettings()
    }

    @objc private func openAutomationPane() {
        Permissions.openAutomationSettings()
    }

    @objc private func restoreDefaults() {
        ShortcutStore.reset(nil)
        for role in ShortcutRole.allCases {
            let defaultScope: WindowScope = (role == .sameApp) ? .activeApp : .allApps
            ShortcutScopeStore.save(defaultScope, for: role)
        }
        UserDefaults.standard.set(false, forKey: "TabStation.overrideCommandTab")
        GeneralPreferences.resetDefaults()
        UserDefaults.standard.set(true, forKey: "TabStation.showAllSpaces")
        UserDefaults.standard.set(false, forKey: "TabStation.showMinimized")
        LaunchAtLogin.setEnabled(false)
        DisplayStyle.current = .thumbnailsOnly
        ThumbnailSize.current = .medium
        AppearancePreferences.resetDefaults()
        FeaturePreferences.resetDefaults()
        reload()
        for role in ShortcutRole.allCases {
            let shortcut = ShortcutStore.load(role)
            let scope = ShortcutScopeStore.load(role)
            onShortcutChange?(role, shortcut)
            onScopeChange?(role, scope)
        }
        onPrimaryChange?(ShortcutStore.load(.primary))
        onGeneralChange?()
        onAppearanceChange?()
    }

    @objc private func done() {
        window?.close()
    }
}
