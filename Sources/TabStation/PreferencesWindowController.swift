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
        scopePopup.addItems(withTitles: ["All apps", "Active app"])
        scopePopup.controlSize = .small
        scopePopup.font = .systemFont(ofSize: 11)
        let currentScope = ShortcutScopeStore.load(role)
        scopePopup.selectItem(withTitle: currentScope.title)
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
        resetButton.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset to default")
        resetButton.toolTip = "Reset to default (\(role.defaultShortcut.displayString))"
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
        scopePopup.selectItem(withTitle: scope.title)
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
        let title = sender.titleOfSelectedItem ?? "All apps"
        let scope: WindowScope = (title == "Active app") ? .activeApp : .allApps
        ShortcutScopeStore.save(scope, for: role)
        onScopeChange?(scope)
    }

    @objc private func resetToDefault() {
        handleChange(role.defaultShortcut)
        let defaultScope: WindowScope = (role == .sameApp) ? .activeApp : .allApps
        ShortcutScopeStore.save(defaultScope, for: role)
        scopePopup.selectItem(withTitle: defaultScope.title)
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
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let screenRecordingStatusLabel = NSTextField(labelWithString: "")
    private let automationStatusLabel = NSTextField(labelWithString: "")

    private let resetButton = NSButton(title: "Restore Defaults", target: nil, action: nil)
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AltDeck Settings"
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
        tabSwitcher.setLabel("Appearance", forSegment: 0)
        tabSwitcher.setLabel("Features", forSegment: 1)
        tabSwitcher.setLabel("Shortcuts", forSegment: 2)
        tabSwitcher.setLabel("General", forSegment: 3)
        tabSwitcher.segmentStyle = .automatic
        tabSwitcher.selectedSegment = 0
        tabSwitcher.target = self
        tabSwitcher.action = #selector(tabChanged)
        tabSwitcher.translatesAutoresizingMaskIntoConstraints = false

        tabView.tabViewType = .noTabsNoBorder
        tabView.translatesAutoresizingMaskIntoConstraints = false

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
        displayStyleControl.setLabel("Thumbnails & Titles", forSegment: 0)
        displayStyleControl.setLabel("Thumbnails Only", forSegment: 1)
        displayStyleControl.setLabel("Icons Only", forSegment: 2)
        displayStyleControl.target = self
        displayStyleControl.action = #selector(displayStyleChanged)

        thumbnailSizeControl.segmentCount = 3
        thumbnailSizeControl.setLabel("Small", forSegment: 0)
        thumbnailSizeControl.setLabel("Medium", forSegment: 1)
        thumbnailSizeControl.setLabel("Large", forSegment: 2)
        thumbnailSizeControl.target = self
        thumbnailSizeControl.action = #selector(thumbnailSizeChanged)

        let layoutCard = makeSectionCard(title: "Layout & Sizing", rows: [
            makeLabeledRow(label: "Mode", control: displayStyleControl),
            makeLabeledRow(label: "Tile Size", control: thumbnailSizeControl),
            makeSwitchRow(
                title: "Auto-adjust size to fit open windows",
                subtitle: "Scales tiles cleanly across multiple rows when many windows are open.",
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
        opacitySlider.widthAnchor.constraint(equalToConstant: 230).isActive = true

        opacityValueLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        opacityValueLabel.textColor = .secondaryLabelColor
        opacityValueLabel.alignment = .right
        opacityValueLabel.translatesAutoresizingMaskIntoConstraints = false
        opacityValueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let opacityRowControl = NSStackView(views: [opacitySlider, opacityValueLabel])
        opacityRowControl.orientation = .horizontal
        opacityRowControl.alignment = .centerY
        opacityRowControl.spacing = 8

        let surfaceCard = makeSectionCard(title: "Liquid Glass & Surface", rows: [
            makeLabeledRow(label: "Theme", control: themeControl),
            makeLabeledRow(label: "Surface", control: backgroundStyleControl),
            makeLabeledRow(label: "Tint Density", control: opacityRowControl),
        ])

        swatchButtons = AccentColorChoice.presets.map { choice in
            AccentSwatchButton(choice: choice, target: self, action: #selector(swatchClicked(_:)))
        }

        customColorWell.target = self
        customColorWell.action = #selector(customColorChanged(_:))
        customColorWell.toolTip = "Custom Highlight Color"
        customColorWell.translatesAutoresizingMaskIntoConstraints = false
        customColorWell.widthAnchor.constraint(equalToConstant: 36).isActive = true
        customColorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true

        var swatchViews: [NSView] = swatchButtons
        swatchViews.append(customColorWell)
        let swatchRow = NSStackView(views: swatchViews)
        swatchRow.orientation = .horizontal
        swatchRow.alignment = .centerY
        swatchRow.spacing = 6

        let highlightCard = makeSectionCard(title: "Selection & Footer", rows: [
            makeLabeledRow(label: "Highlight", control: swatchRow),
            makeSwitchRow(
                title: "Show shortcut hints in footer",
                subtitle: "Displays an unobtrusive bottom legend bar in thumbnail modes.",
                toggle: showFooterHintsSwitch,
                action: #selector(toggleShowFooterHints)
            ),
        ])

        return makeCardStack([layoutCard, surfaceCard, highlightCard])
    }

    private func buildFeaturesTab() -> NSView {
        let previewCard = makeSectionCard(title: "Preview & Hover Controls", rows: [
            makeSwitchRow(
                title: "Hold-to-Preview when pausing on an icon",
                subtitle: "In Icons Only mode, rest briefly on an icon while holding Command/Option to peek the window.",
                toggle: autoPreviewOnHoldSwitch,
                action: #selector(toggleAutoPreviewOnHold)
            ),
            makeSwitchRow(
                title: "Spacebar persistent Quick Look (Space)",
                subtitle: "Press Space to lock a floating window preview open as you switch.",
                toggle: spaceQuickLookSwitch,
                action: #selector(toggleSpaceQuickLook)
            ),
            makeSwitchRow(
                title: "Hover Quick-Action Pills",
                subtitle: "Show left/right snap and close buttons when moving the pointer over thumbnails.",
                toggle: hoverActionPillsSwitch,
                action: #selector(toggleHoverActionPills)
            ),
        ])

        let workspaceCard = makeSectionCard(title: "Window Tiling & Navigation", rows: [
            makeSwitchRow(
                title: "Arrow-Key Window Snapping (← / → / ↑ / ↓ & C)",
                subtitle: "Snap the selected window to screen halves or maximize. Turn off to rotate icons with arrow keys.",
                toggle: arrowKeySnappingSwitch,
                action: #selector(toggleArrowKeySnapping)
            ),
            makeSwitchRow(
                title: "Move Window Across Displays (D)",
                subtitle: "Send the selected window directly to your next connected monitor.",
                toggle: displayMoveShortcutSwitch,
                action: #selector(toggleDisplayMoveShortcut)
            ),
            makeSwitchRow(
                title: "Float Window on Top / PiP (P)",
                subtitle: "Pin any window into a live ScreenCaptureKit Picture-in-Picture overlay with Ghost Mode.",
                toggle: pinShortcutSwitch,
                action: #selector(togglePinShortcut)
            ),
        ])

        let browserCard = makeSectionCard(title: "Browser & App Sources", rows: [
            makeSwitchRow(
                title: "Browser Tab Filter Shortcut (S)",
                subtitle: "Press S in the switcher to jump to open tabs from Chrome, Safari, Arc, Edge, and Brave.",
                toggle: browserTabsShortcutSwitch,
                action: #selector(toggleBrowserTabsShortcut)
            ),
            makeSwitchRow(
                title: "Show Browser Tabs in Main List by Default",
                subtitle: "Always mix open browser tabs into the main switcher strip instead of only showing them on S.",
                toggle: includeBrowserTabsSwitch,
                action: #selector(toggleIncludeBrowserTabs)
            ),
        ])

        return makeCardStack([previewCard, workspaceCard, browserCard])
    }

    private func buildShortcutsTab() -> NSView {
        let intro = NSTextField(wrappingLabelWithString:
            "Hold a shortcut, tap its key to cycle windows, then release to switch.")
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
        let behaviorCard = makeSectionCard(title: "Behavior & System Integration", rows: [
            makeSwitchRow(
                title: "Override ⌘Tab",
                subtitle: "Replace the built-in macOS application switcher with AltDeck.",
                toggle: overrideCommandTabSwitch,
                action: #selector(toggleOverrideCommandTab)
            ),
            makeSwitchRow(
                title: "Follow Active Display",
                subtitle: "Bring the switched window onto the monitor under your cursor if needed.",
                toggle: followActiveDisplaySwitch,
                action: #selector(toggleFollowActiveDisplay)
            ),
            makeSwitchRow(
                title: "Show Windows from All Spaces",
                subtitle: "Include windows from other desktops and full-screen Spaces.",
                toggle: showAllSpacesSwitch,
                action: #selector(toggleShowAllSpaces)
            ),
            makeSwitchRow(
                title: "Include Minimized Windows",
                subtitle: "Keep Dock-minimized windows selectable and auto-restore on switch.",
                toggle: showMinimizedSwitch,
                action: #selector(toggleShowMinimized)
            ),
            makeSwitchRow(
                title: "Launch AltDeck at Login",
                subtitle: "Start automatically in the background whenever you log in.",
                toggle: launchAtLoginSwitch,
                action: #selector(toggleLaunchAtLogin)
            ),
        ])

        let permCard = makeSectionCard(title: "macOS Permissions", rows: [
            makePermissionRow(
                title: "Accessibility",
                subtitle: "Required for global hotkeys and raising specific app windows.",
                statusLabel: accessibilityStatusLabel,
                action: #selector(openAccessibilityPane)
            ),
            makePermissionRow(
                title: "Screen Recording",
                subtitle: "Required for live window previews and reading offscreen window titles.",
                statusLabel: screenRecordingStatusLabel,
                action: #selector(openScreenRecordingPane)
            ),
            makePermissionRow(
                title: "Automation (Browsers)",
                subtitle: "Required for listing and switching Chrome, Safari, Edge, Brave, and Arc tabs.",
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

        let openBtn = NSButton(title: "System Settings…", target: self, action: action)
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
        accessibilityStatusLabel.stringValue = axOK ? "● Granted" : "● Needed"
        accessibilityStatusLabel.textColor = axOK ? .systemGreen : .systemOrange

        let srOK = Permissions.screenRecordingGranted
        screenRecordingStatusLabel.stringValue = srOK ? "● Granted" : "● Optional"
        screenRecordingStatusLabel.textColor = srOK ? .systemGreen : .secondaryLabelColor

        switch Permissions.automationStatus(forBundleIDs: BrowserTabService.shared.supportedBundleIDs) {
        case .granted:
            automationStatusLabel.stringValue = "● Granted"
            automationStatusLabel.textColor = .systemGreen
        case .promptable:
            automationStatusLabel.stringValue = "● Pending"
            automationStatusLabel.textColor = .systemOrange
        case .denied:
            automationStatusLabel.stringValue = "● Denied"
            automationStatusLabel.textColor = .systemRed
        case .unavailable:
            automationStatusLabel.stringValue = "● Idle"
            automationStatusLabel.textColor = .secondaryLabelColor
        }

        refreshLegend()
    }

    private func refreshLegend() {
        let all = ShortcutStore.loadAll()
        let p = all[.primary] ?? .optionTab
        let s = all[.sameApp] ?? Shortcut(modifiers: [.option], keyCode: KeyCode.grave)
        legendLabel.stringValue = "\(p.displayString) next · \(s.displayString) same app · esc cancel"
    }

    // MARK: - Actions

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        tabView.selectTabViewItem(at: sender.selectedSegment)
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
        Permissions.openAccessibilitySettings()
    }

    @objc private func openScreenRecordingPane() {
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
