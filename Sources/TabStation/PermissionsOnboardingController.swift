import AppKit

/// Clean, non-overlapping first-launch permissions setup window.
/// Replaces silent first-launch failure for LSUIElement users and avoids
/// stacking Accessibility + Screen Recording system prompts simultaneously.
final class PermissionsOnboardingController: NSWindowController {

    private var timer: Timer?
    private var axStatusLabel = NSTextField(labelWithString: "")
    private var srStatusLabel = NSTextField(labelWithString: "")
    private var axButton = NSButton(title: "", target: nil, action: nil)
    private var srButton = NSButton(title: "", target: nil, action: nil)
    private var primaryButton = NSButton(title: "", target: nil, action: nil)
    private var secondaryButton = NSButton(title: "", target: nil, action: nil)
    private var hintLabel = NSTextField(wrappingLabelWithString: "")

    private var initialScreenRecordingGranted = Permissions.screenRecordingGranted
    private var didTriggerAxPromptThisSession = false

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 392),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        self.init(window: window)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceNotification),
            name: .tabStationAppearanceChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBecomeActiveNotification),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        rebuildUI()
        refreshStatus()
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        initialScreenRecordingGranted = Permissions.screenRecordingGranted
        rebuildUI()
        refreshStatus()
        startPolling()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    override func close() {
        timer?.invalidate()
        timer = nil
        super.close()
    }

    // MARK: - UI

    private func rebuildUI() {
        guard let window else { return }
        window.title = L10n.t("AltDeck Setup", "欢迎使用 AltDeck")

        let root = NSView(frame: window.contentRect(forFrameRect: window.frame))
        root.wantsLayer = true

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let titleField = NSTextField(labelWithString: L10n.t(
            "Enable AltDeck Permissions",
            "开启 AltDeck 系统权限"
        ))
        titleField.font = .systemFont(ofSize: 16, weight: .bold)
        titleField.textColor = .labelColor

        let subtitleField = NSTextField(wrappingLabelWithString: L10n.t(
            "AltDeck runs locally with zero telemetry. Grant Accessibility first so your ⌥Tab shortcut works.",
            "AltDeck 完全本地离线运行，零遥测收集。请先授予“辅助功能”权限以启用快捷键切窗。"
        ))
        subtitleField.font = .systemFont(ofSize: 12)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.maximumNumberOfLines = 2

        let headerText = NSStackView(views: [titleField, subtitleField])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 4

        let headerRow = NSStackView(views: [iconView, headerText])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 14
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        axStatusLabel = NSTextField(labelWithString: "")
        srStatusLabel = NSTextField(labelWithString: "")

        axButton = NSButton(
            title: L10n.t("Grant Accessibility…", "授权辅助功能…"),
            target: self,
            action: #selector(requestAccessibilityClicked)
        )
        srButton = NSButton(
            title: L10n.t("Grant Screen Recording…", "授权屏幕录制…"),
            target: self,
            action: #selector(requestScreenRecordingClicked)
        )

        let axCard = makeStepCard(
            symbol: "hand.raised.fill",
            title: L10n.t("1. Accessibility (Required)", "1. 辅助功能（必需）"),
            subtitle: L10n.t(
                "Captures your shortcut globally and brings the exact window you select to the front.",
                "用于监听全局快捷键，并将你选中的指定窗口精准置前。"
            ),
            statusLabel: axStatusLabel,
            button: axButton
        )

        let srCard = makeStepCard(
            symbol: "rectangle.dashed.badge.record",
            title: L10n.t("2. Screen Recording (Recommended)", "2. 屏幕录制（推荐）"),
            subtitle: L10n.t(
                "Powers live window thumbnails, titles, and Picture-in-Picture. Skip if using Icons Only mode.",
                "用于生成实时窗口缩略图、标题与画中画悬浮窗；仅使用图标模式可跳过。"
            ),
            statusLabel: srStatusLabel,
            button: srButton
        )

        hintLabel = NSTextField(wrappingLabelWithString: "")
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.maximumNumberOfLines = 2
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        secondaryButton = NSButton(
            title: L10n.t("Later", "稍后设置"),
            target: self,
            action: #selector(laterClicked)
        )
        secondaryButton.bezelStyle = .rounded

        primaryButton = NSButton(
            title: L10n.t("Done", "完成并开始使用"),
            target: self,
            action: #selector(primaryClicked)
        )
        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let footerRow = NSStackView(views: [secondaryButton, spacer, primaryButton])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [headerRow, axCard, srCard, hintLabel, footerRow])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            headerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            axCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            srCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            hintLabel.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            footerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])

        window.contentView = root
    }

    private func makeStepCard(
        symbol: String,
        title: String,
        subtitle: String,
        statusLabel: NSTextField,
        button: NSButton
    ) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 11
        box.layer?.cornerCurve = .continuous
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .labelColor

        statusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [titleField, spacer, statusLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY

        let subtitleField = NSTextField(wrappingLabelWithString: subtitle)
        subtitleField.font = .systemFont(ofSize: 11.5)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.maximumNumberOfLines = 2

        button.bezelStyle = .rounded
        button.controlSize = .small
        button.setContentHuggingPriority(.required, for: .horizontal)

        let bottomRow = NSStackView(views: [subtitleField, button])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.spacing = 10

        let textColumn = NSStackView(views: [topRow, bottomRow])
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 4

        let row = NSStackView(views: [icon, textColumn])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            topRow.widthAnchor.constraint(equalTo: textColumn.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: textColumn.widthAnchor),
        ])
        return box
    }

    // MARK: - Polling & State

    private func startPolling() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func handleAppearanceNotification() {
        rebuildUI()
        refreshStatus()
    }

    @objc private func handleBecomeActiveNotification() {
        refreshStatus()
    }

    func refreshStatus() {
        let axGranted = Permissions.accessibilityGranted
        let srGranted = Permissions.screenRecordingGranted

        axStatusLabel.stringValue = axGranted
            ? L10n.t("● Granted", "● 已授权")
            : L10n.t("● Required", "● 需授权")
        axStatusLabel.textColor = axGranted ? .systemGreen : .systemOrange
        axButton.isEnabled = !axGranted
        axButton.title = axGranted
            ? L10n.t("Enabled", "已开启")
            : L10n.t("Grant Accessibility…", "授权辅助功能…")

        srStatusLabel.stringValue = srGranted
            ? L10n.t("● Granted", "● 已授权")
            : L10n.t("● Optional", "● 可选")
        srStatusLabel.textColor = srGranted ? .systemGreen : .secondaryLabelColor
        srButton.isEnabled = !srGranted
        srButton.title = srGranted
            ? L10n.t("Enabled", "已开启")
            : L10n.t("Grant Screen Recording…", "授权屏幕录制…")

        let needsRelaunchForSR = srGranted && !initialScreenRecordingGranted
        if needsRelaunchForSR {
            hintLabel.stringValue = L10n.t(
                "Screen Recording was just enabled. Relaunch AltDeck so window thumbnails start immediately.",
                "已开启屏幕录制权限，点击右侧“重启 AltDeck”后缩略图预览将立即生效。"
            )
            primaryButton.title = L10n.t("Relaunch AltDeck", "重启 AltDeck")
            primaryButton.isEnabled = true
        } else if axGranted {
            let shortcut = ShortcutStore.load(.primary).displayString
            hintLabel.stringValue = L10n.t(
                "Ready! AltDeck lives cleanly in the top menu bar — hold \(shortcut) to switch windows anytime.",
                "准备就绪！AltDeck 已驻留在顶部菜单栏，随时按住 \(shortcut) 即可切换窗口。"
            )
            primaryButton.title = L10n.t("Start Using AltDeck", "开始使用 AltDeck")
            primaryButton.isEnabled = true
        } else {
            hintLabel.stringValue = L10n.t(
                "Click “Grant Accessibility…” above and toggle AltDeck ON in System Settings → Privacy & Security.",
                "点击上方“授权辅助功能…”，并在 系统设置 → 隐私与安全性 中开启 AltDeck。"
            )
            primaryButton.title = L10n.t("Done", "完成")
            primaryButton.isEnabled = true
        }
    }

    // MARK: - Actions

    @objc private func requestAccessibilityClicked() {
        if !didTriggerAxPromptThisSession {
            didTriggerAxPromptThisSession = true
            Permissions.requestAccessibility()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if !Permissions.accessibilityGranted {
                    Permissions.openAccessibilitySettings()
                }
            }
        } else {
            Permissions.openAccessibilitySettings()
        }
    }

    @objc private func requestScreenRecordingClicked() {
        Permissions.requestScreenRecording()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if !Permissions.screenRecordingGranted {
                Permissions.openScreenRecordingSettings()
            }
        }
    }

    @objc private func laterClicked() {
        close()
    }

    @objc private func primaryClicked() {
        let needsRelaunchForSR = Permissions.screenRecordingGranted && !initialScreenRecordingGranted
        if needsRelaunchForSR {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
            NSApp.terminate(nil)
        } else {
            close()
        }
    }
}
