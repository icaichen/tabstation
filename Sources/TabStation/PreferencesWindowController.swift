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

/// Tabbed Preferences window: Appearance, Shortcuts, and General settings.
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
    private let autoAdjustSizeCheckbox = NSButton(checkboxWithTitle: "Auto-adjust size based on open windows", target: nil, action: nil)
    private let themeControl = NSSegmentedControl()
    private let backgroundStyleControl = NSSegmentedControl()
    private let opacitySlider = NSSlider(value: 0.85, minValue: 0.30, maxValue: 1.0, target: nil, action: nil)
    private let opacityValueLabel = NSTextField(labelWithString: "85%")
    private var swatchButtons: [AccentSwatchButton] = []
    private let customColorWell = NSColorWell()
    private let autoPreviewOnHoldCheckbox = NSButton(checkboxWithTitle: "Show window preview when pausing on an icon", target: nil, action: nil)
    private let showFooterHintsCheckbox = NSButton(checkboxWithTitle: "Show shortcut hints in footer", target: nil, action: nil)

    // General controls
    private let overrideCommandTabCheckbox = NSButton(checkboxWithTitle: "Override ⌘Tab (replaces macOS app switcher)", target: nil, action: nil)
    private let followActiveDisplayCheckbox = NSButton(checkboxWithTitle: "Follow active display (summon window to current monitor on switch)", target: nil, action: nil)
    private let showAllSpacesCheckbox = NSButton(checkboxWithTitle: "Show windows from all Spaces & full-screen apps", target: nil, action: nil)
    private let showMinimizedCheckbox = NSButton(checkboxWithTitle: "Show minimized windows in switcher", target: nil, action: nil)
    private let includeBrowserTabsCheckbox = NSButton(checkboxWithTitle: "Include open browser tabs (Chrome, Safari, Edge, Arc)", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch TabStation at login", target: nil, action: nil)

    private let resetButton = NSButton(title: "Restore Defaults", target: nil, action: nil)
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TabStation Settings"
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

        tabSwitcher.segmentCount = 3
        tabSwitcher.setLabel("Appearance", forSegment: 0)
        tabSwitcher.setLabel("Shortcuts", forSegment: 1)
        tabSwitcher.setLabel("General", forSegment: 2)
        tabSwitcher.segmentStyle = .automatic
        tabSwitcher.selectedSegment = 0
        tabSwitcher.target = self
        tabSwitcher.action = #selector(tabChanged)
        tabSwitcher.translatesAutoresizingMaskIntoConstraints = false

        tabView.tabViewType = .noTabsNoBorder
        tabView.translatesAutoresizingMaskIntoConstraints = false

        let appearanceTab = NSTabViewItem(identifier: "appearance")
        appearanceTab.view = buildAppearanceTab()
        tabView.addTabViewItem(appearanceTab)

        let shortcutsTab = NSTabViewItem(identifier: "shortcuts")
        shortcutsTab.view = buildShortcutsTab()
        tabView.addTabViewItem(shortcutsTab)

        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.view = buildGeneralTab()
        tabView.addTabViewItem(generalTab)

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

            tabView.topAnchor.constraint(equalTo: topSeparator.bottomAnchor, constant: 14),
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            tabView.bottomAnchor.constraint(equalTo: bottomSeparator.topAnchor, constant: -14),

            bottomSeparator.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            bottomSeparator.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            bottomSeparator.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),

            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    private func buildAppearanceTab() -> NSView {
        let container = NSView()

        // Layout & Sizing card
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

        autoAdjustSizeCheckbox.font = .systemFont(ofSize: 12)
        autoAdjustSizeCheckbox.target = self
        autoAdjustSizeCheckbox.action = #selector(toggleAutoAdjustSize)

        let layoutCard = makeSectionCard(title: "Layout & Sizing", rows: [
            makeLabeledRow(label: "Mode", control: displayStyleControl),
            makeLabeledRow(label: "Tile Size", control: thumbnailSizeControl),
            autoAdjustSizeCheckbox
        ])

        // Theme & Transparency card
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
        opacitySlider.widthAnchor.constraint(equalToConstant: 210).isActive = true

        opacityValueLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        opacityValueLabel.textColor = .secondaryLabelColor
        opacityValueLabel.alignment = .right
        opacityValueLabel.translatesAutoresizingMaskIntoConstraints = false
        opacityValueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let opacityRowControl = NSStackView(views: [opacitySlider, opacityValueLabel])
        opacityRowControl.orientation = .horizontal
        opacityRowControl.alignment = .centerY
        opacityRowControl.spacing = 8

        let surfaceCard = makeSectionCard(title: "Surface & Transparency", rows: [
            makeLabeledRow(label: "Theme", control: themeControl),
            makeLabeledRow(label: "Background", control: backgroundStyleControl),
            makeLabeledRow(label: "Opacity", control: opacityRowControl)
        ])

        // Highlight & Hints card
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

        autoPreviewOnHoldCheckbox.font = .systemFont(ofSize: 12)
        autoPreviewOnHoldCheckbox.target = self
        autoPreviewOnHoldCheckbox.action = #selector(toggleAutoPreviewOnHold)

        showFooterHintsCheckbox.font = .systemFont(ofSize: 12)
        showFooterHintsCheckbox.target = self
        showFooterHintsCheckbox.action = #selector(toggleShowFooterHints)

        let highlightCard = makeSectionCard(title: "Selection & Preview", rows: [
            makeLabeledRow(label: "Highlight", control: swatchRow),
            autoPreviewOnHoldCheckbox,
            showFooterHintsCheckbox
        ])

        let mainStack = NSStackView(views: [layoutCard, surfaceCard, highlightCard])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: container.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            layoutCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            surfaceCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            highlightCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])

        return container
    }

    private func buildShortcutsTab() -> NSView {
        let container = NSView()

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

        let stack = NSStackView(views: stackViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        var constraints: [NSLayoutConstraint] = [
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            intro.widthAnchor.constraint(equalTo: stack.widthAnchor),
            legendLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ]
        for row in rows.values {
            constraints.append(row.widthAnchor.constraint(equalTo: stack.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)

        return container
    }

    private func buildGeneralTab() -> NSView {
        let container = NSView()

        let checkboxes: [(NSButton, Selector)] = [
            (overrideCommandTabCheckbox, #selector(toggleOverrideCommandTab)),
            (followActiveDisplayCheckbox, #selector(toggleFollowActiveDisplay)),
            (showAllSpacesCheckbox, #selector(toggleShowAllSpaces)),
            (showMinimizedCheckbox, #selector(toggleShowMinimized)),
            (includeBrowserTabsCheckbox, #selector(toggleIncludeBrowserTabs)),
            (launchAtLoginCheckbox, #selector(toggleLaunchAtLogin))
        ]
        for (button, action) in checkboxes {
            button.font = .systemFont(ofSize: 12.5)
            button.target = self
            button.action = action
        }

        let card = makeSectionCard(title: "Behavior & Integration", rows: checkboxes.map(\.0))
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        return container
    }

    private func makeSectionCard(title: String, rows: [NSView]) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .secondaryLabelColor

        var allViews: [NSView] = [header]
        allViews.append(contentsOf: rows)

        let stack = NSStackView(views: allViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
        ])
        return box
    }

    private func makeLabeledRow(label: String, control: NSView) -> NSView {
        let titleField = NSTextField(labelWithString: label)
        titleField.font = .systemFont(ofSize: 12)
        titleField.textColor = .labelColor
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.widthAnchor.constraint(equalToConstant: 84).isActive = true

        let row = NSStackView(views: [titleField, control])
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
        overrideCommandTabCheckbox.state = UserDefaults.standard.bool(forKey: "TabStation.overrideCommandTab") ? .on : .off
        followActiveDisplayCheckbox.state = UserDefaults.standard.bool(forKey: "TabStation.followActiveDisplay") ? .on : .off
        let allSpaces = UserDefaults.standard.object(forKey: "TabStation.showAllSpaces") as? Bool ?? true
        showAllSpacesCheckbox.state = allSpaces ? .on : .off
        showMinimizedCheckbox.state = UserDefaults.standard.bool(forKey: "TabStation.showMinimized") ? .on : .off
        includeBrowserTabsCheckbox.state = UserDefaults.standard.bool(forKey: "TabStation.includeBrowserTabs") ? .on : .off
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off

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

        autoAdjustSizeCheckbox.state = AppearancePreferences.autoAdjustSize ? .on : .off
        autoPreviewOnHoldCheckbox.state = AppearancePreferences.autoPreviewOnHold ? .on : .off
        showFooterHintsCheckbox.state = AppearancePreferences.showFooterHints ? .on : .off

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

    @objc private func toggleAutoAdjustSize(_ sender: NSButton) {
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

    @objc private func toggleAutoPreviewOnHold(_ sender: NSButton) {
        AppearancePreferences.autoPreviewOnHold = sender.state == .on
        onAppearanceChange?()
    }

    @objc private func toggleShowFooterHints(_ sender: NSButton) {
        AppearancePreferences.showFooterHints = sender.state == .on
        onAppearanceChange?()
    }

    @objc private func toggleOverrideCommandTab(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "TabStation.overrideCommandTab")
        onGeneralChange?()
    }

    @objc private func toggleFollowActiveDisplay(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "TabStation.followActiveDisplay")
        onGeneralChange?()
    }

    @objc private func toggleShowAllSpaces(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "TabStation.showAllSpaces")
        WindowListCache.shared.invalidateAndPrewarm()
        onGeneralChange?()
    }

    @objc private func toggleShowMinimized(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "TabStation.showMinimized")
        onGeneralChange?()
    }

    @objc private func toggleIncludeBrowserTabs(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "TabStation.includeBrowserTabs")
        onGeneralChange?()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        LaunchAtLogin.setEnabled(sender.state == .on)
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func restoreDefaults() {
        ShortcutStore.reset(nil)
        for role in ShortcutRole.allCases {
            let defaultScope: WindowScope = (role == .sameApp) ? .activeApp : .allApps
            ShortcutScopeStore.save(defaultScope, for: role)
        }
        UserDefaults.standard.set(false, forKey: "TabStation.overrideCommandTab")
        UserDefaults.standard.set(false, forKey: "TabStation.followActiveDisplay")
        UserDefaults.standard.set(true, forKey: "TabStation.showAllSpaces")
        UserDefaults.standard.set(false, forKey: "TabStation.showMinimized")
        UserDefaults.standard.set(false, forKey: "TabStation.includeBrowserTabs")
        LaunchAtLogin.setEnabled(false)
        DisplayStyle.current = .full
        ThumbnailSize.current = .medium
        AppearancePreferences.resetDefaults()
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
