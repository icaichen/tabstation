import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let interceptor = HotKeyInterceptor()
    private lazy var controller = SwitcherController()
    private lazy var preferences = PreferencesWindowController()
    private lazy var onboarding = PermissionsOnboardingController()
    private var statusItem: NSStatusItem?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyDefaultsIfNeeded()
        Theme.configure()

        installMainMenu()
        installStatusItem()
        installHotKeys()
        setupPreferencesHandlers()
        handlePermissions()
        UpdateManager.shared.schedulePeriodicChecks()
    }

    /// Older builds defaulted `includeBrowserTabs` to enabled; reset it once so the
    /// default switcher shows only apps/windows until the user presses `S` (or opts in).
    private func migrateLegacyDefaultsIfNeeded() {
        let key = "TabStation.defaultsSchemaVersion"
        let current = UserDefaults.standard.integer(forKey: key)
        if current < 2 {
            UserDefaults.standard.removeObject(forKey: "TabStation.includeBrowserTabs")
            UserDefaults.standard.set(2, forKey: key)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        interceptor.uninstall()
    }

    // MARK: - Hot keys

    private func installHotKeys() {
        let all = ShortcutStore.loadAll()
        interceptor.primaryShortcut = all[.primary] ?? .optionTab
        interceptor.sameAppShortcut = all[.sameApp] ?? Shortcut(modifiers: [.option], keyCode: KeyCode.grave)
        interceptor.overrideCommandTab = UserDefaults.standard.bool(forKey: "TabStation.overrideCommandTab")

        interceptor.onImmediateHide = { [weak self] in
            self?.controller.hidePanelImmediately()
        }
        interceptor.onKey = { [weak self] key in
            guard let self else { return }
            self.controller.handle(key)
            // Keep the event tap's synchronous view of "is the switcher up" in
            // sync with reality, so it knows whether to swallow ⌥/esc.
            self.interceptor.isSwitcherVisible = self.controller.isVisible
        }

        // Connect switcher open/close callbacks for hold-modifier tracking
        controller.onSwitcherOpen = { [weak self] role in
            self?.interceptor.switcherDidOpen(with: role)
        }
        controller.onSwitcherClose = { [weak self] in
            self?.interceptor.switcherDidClose()
        }

        if !interceptor.install() {
            // Accessibility is not granted yet; `handlePermissions()` presents the
            // step-by-step setup window, and the DistributedNotificationCenter observer
            // below installs the CGEventTap automatically as soon as the user enables it.
        }

        // Automatically enable CGEventTap without requiring a relaunch once the user grants Accessibility.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard let self, Permissions.accessibilityGranted else { return }
                _ = self.interceptor.install()
            }
        }

        // Re-enable CGEventTap after macOS sleep/wake if WindowServer disabled it.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.interceptor.ensureTapActive()
        }
    }

    // MARK: - Permissions

    private func handlePermissions() {
        guard !Permissions.accessibilityGranted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.onboarding.show()
        }
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let icon = Self.makeMenuBarLogoImage()
            icon.accessibilityDescription = "AltDeck"
            button.image = icon
            button.toolTip = L10n.t("AltDeck — hold ⌥ and tap Tab", "AltDeck — 按住 ⌥ 点按 Tab")
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        NotificationCenter.default.addObserver(
            forName: .altDeckUpdateStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatusItemUpdateBadge()
        }
        refreshStatusItemUpdateBadge()
    }

    /// Standard invisible menu bar shortcuts (⌘W close, ⌘M minimize, ⌘C/V/A edit, ⌘, settings, ⌘Q quit)
    /// for accessory windows like Settings, Software Update, and Onboarding.
    func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let prefsItem = NSMenuItem(
            title: L10n.t("Preferences…", "设置…"),
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        appMenu.addItem(prefsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: L10n.t("Quit AltDeck", "退出 AltDeck"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: L10n.t("Close Window", "关闭窗口"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: L10n.t("Cut", "剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.t("Copy", "拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.t("Paste", "粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.t("Select All", "全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: L10n.t("Minimize", "最小化"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    /// Vector template silhouette matching AltDeck's stacked-window-cards logo (18x18pt, Dark/Light menu bar adaptive).
    static func makeMenuBarLogoImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }

            let cards: [(rect: NSRect, fillAlpha: CGFloat, strokeAlpha: CGFloat, lineWidth: CGFloat)] = [
                (NSRect(x: 1.6, y: 6.4, width: 9.8, height: 8.6), 0.16, 0.62, 1.1),
                (NSRect(x: 4.1, y: 4.3, width: 9.8, height: 8.6), 0.28, 0.82, 1.2),
                (NSRect(x: 6.6, y: 2.2, width: 9.8, height: 8.6), 0.14, 1.00, 1.4),
            ]

            for (index, card) in cards.enumerated() {
                let path = NSBezierPath(roundedRect: card.rect, xRadius: 2.2, yRadius: 2.2)
                if index > 0 {
                    NSGraphicsContext.current?.compositingOperation = .clear
                    let maskPath = NSBezierPath(
                        roundedRect: card.rect.insetBy(dx: -0.4, dy: -0.4),
                        xRadius: 2.4,
                        yRadius: 2.4
                    )
                    maskPath.fill()
                    NSGraphicsContext.current?.compositingOperation = .sourceOver
                }

                NSColor.black.withAlphaComponent(card.fillAlpha).setFill()
                path.fill()

                NSColor.black.withAlphaComponent(card.strokeAlpha).setStroke()
                path.lineWidth = card.lineWidth
                path.stroke()
            }

            // Crisp active window header bar inside the frontmost card
            let headerRect = NSRect(x: 8.1, y: 8.2, width: 6.8, height: 1.4)
            let headerPath = NSBezierPath(roundedRect: headerRect, xRadius: 0.7, yRadius: 0.7)
            NSColor.black.withAlphaComponent(0.95).setFill()
            headerPath.fill()

            return true
        }
        image.isTemplate = true
        return image
    }

    private func refreshStatusItemUpdateBadge() {
        guard let button = statusItem?.button else { return }
        if let release = UpdateManager.shared.availableRelease {
            button.toolTip = L10n.t(
                "AltDeck — Update Available (v\(release.version))",
                "AltDeck — 发现新版本 (v\(release.version))"
            )
        } else {
            button.toolTip = L10n.t("AltDeck — hold ⌥ and tap Tab", "AltDeck — 按住 ⌥ 点按 Tab")
        }
    }

    // MARK: - Actions

    private func setupPreferencesHandlers() {
        preferences.onShortcutChange = { [weak self] role, shortcut in
            guard let self else { return }
            switch role {
            case .primary:
                self.interceptor.primaryShortcut = shortcut
                self.statusItem?.button?.toolTip = L10n.t(
                    "AltDeck — hold \(shortcut.displayString)",
                    "AltDeck — 按住 \(shortcut.displayString)"
                )
            case .sameApp:
                self.interceptor.sameAppShortcut = shortcut
            }
        }
        preferences.onScopeChange = { [weak self] _, _ in
            guard let self else { return }
            self.interceptor.updateCarbonHotKeys()
        }
        preferences.onGeneralChange = { [weak self] in
            guard let self else { return }
            self.interceptor.overrideCommandTab = UserDefaults.standard.bool(forKey: "TabStation.overrideCommandTab")
        }
    }

    @objc private func showPreferences() {
        preferences.show()
    }

    @objc private func toggleOverrideCommandTab() {
        let current = UserDefaults.standard.bool(forKey: "TabStation.overrideCommandTab")
        let updated = !current
        UserDefaults.standard.set(updated, forKey: "TabStation.overrideCommandTab")
        interceptor.overrideCommandTab = updated
    }

    @objc private func toggleShowMinimized() {
        let current = UserDefaults.standard.bool(forKey: "TabStation.showMinimized")
        UserDefaults.standard.set(!current, forKey: "TabStation.showMinimized")
    }

    @objc private func toggleIncludeBrowserTabs() {
        FeaturePreferences.includeBrowserTabsByDefault.toggle()
        WindowListCache.shared.invalidateAndPrewarm()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
    }

    @objc private func setDisplayStyleFull() {
        DisplayStyle.current = .full
    }

    @objc private func setDisplayStyleThumbnailsOnly() {
        DisplayStyle.current = .thumbnailsOnly
    }

    @objc private func setDisplayStyleIconsOnly() {
        DisplayStyle.current = .iconsOnly
    }

    @objc private func disableGhostMode() {
        PinManager.shared.disableGhostModeForAll()
    }

    @objc private func closeAllPiP() {
        PinManager.shared.unpinAll()
    }

    @objc private func setThumbnailSizeSmall() {
        ThumbnailSize.current = .small
    }

    @objc private func setThumbnailSizeMedium() {
        ThumbnailSize.current = .medium
    }

    @objc private func setThumbnailSizeLarge() {
        ThumbnailSize.current = .large
    }

    @objc private func toggleShowFooterHints() {
        AppearancePreferences.showFooterHints.toggle()
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func openScreenRecordingSettings() {
        Permissions.openScreenRecordingSettings()
    }

    @objc private func requestPermissions() {
        onboarding.show()
    }

    @objc private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        )
        NSApp.terminate(nil)
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdatesManually()
    }

    @objc private func openAvailableUpdate() {
        UpdateManager.shared.presentUpdateWindow()
    }

    @objc private func openWebsite() {
        NSWorkspace.shared.open(UpdateManager.websiteURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Status menu

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let accessibility = Permissions.accessibilityGranted
        let screenRecording = Permissions.screenRecordingGranted

        let title = NSMenuItem(
            title: "AltDeck v\(UpdateManager.shared.currentVersion)",
            action: nil,
            keyEquivalent: ""
        )
        title.isEnabled = false
        menu.addItem(title)

        if let release = UpdateManager.shared.availableRelease {
            let updateItem = NSMenuItem(
                title: L10n.t(
                    "Update Available: v\(release.version)…",
                    "发现新版本：v\(release.version)…"
                ),
                action: #selector(openAvailableUpdate),
                keyEquivalent: ""
            )
            updateItem.target = self
            updateItem.image = NSImage(
                systemSymbolName: "arrow.down.circle.fill",
                accessibilityDescription: nil
            )
            updateItem.image?.isTemplate = true
            menu.addItem(updateItem)
        }
        menu.addItem(.separator())

        menu.addItem(permissionRow(
            label: L10n.t("Accessibility", "辅助功能"),
            granted: accessibility,
            action: #selector(openAccessibilitySettings)
        ))
        menu.addItem(permissionRow(
            label: L10n.t("Screen Recording", "屏幕录制"),
            granted: screenRecording,
            action: #selector(openScreenRecordingSettings)
        ))

        if !accessibility || !screenRecording {
            menu.addItem(.separator())
            let request = NSMenuItem(
                title: L10n.t("Request Permissions…", "请求系统权限…"),
                action: #selector(requestPermissions),
                keyEquivalent: ""
            )
            request.target = self
            menu.addItem(request)
        }

        menu.addItem(.separator())

        let shortcutStr = ShortcutStore.load().displayString
        let shortcuts = NSMenuItem(
            title: L10n.t("Hold \(shortcutStr) to switch windows", "按住 \(shortcutStr) 切换窗口"),
            action: nil,
            keyEquivalent: ""
        )
        shortcuts.isEnabled = false
        menu.addItem(shortcuts)

        menu.addItem(.separator())

        let overrideItem = NSMenuItem(
            title: L10n.t("Override ⌘Tab", "接管系统 ⌘Tab"),
            action: #selector(toggleOverrideCommandTab),
            keyEquivalent: ""
        )
        overrideItem.target = self
        overrideItem.state = UserDefaults.standard.bool(forKey: "TabStation.overrideCommandTab") ? .on : .off
        menu.addItem(overrideItem)

        let minItem = NSMenuItem(
            title: L10n.t("Show Minimized Windows", "显示已最小化窗口"),
            action: #selector(toggleShowMinimized),
            keyEquivalent: ""
        )
        minItem.target = self
        minItem.state = UserDefaults.standard.bool(forKey: "TabStation.showMinimized") ? .on : .off
        menu.addItem(minItem)

        let includeTabsItem = NSMenuItem(
            title: L10n.t("Show Browser Tabs in Main List", "默认在主列表中显示浏览器标签页"),
            action: #selector(toggleIncludeBrowserTabs),
            keyEquivalent: ""
        )
        includeTabsItem.target = self
        includeTabsItem.state = FeaturePreferences.includeBrowserTabsByDefault ? .on : .off
        menu.addItem(includeTabsItem)

        let loginItem = NSMenuItem(
            title: L10n.t("Launch at Login", "开机自动启动"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(loginItem)

        if PinManager.shared.hasPinnedWindows {
            menu.addItem(.separator())
            let pipTitle = NSMenuItem(title: L10n.t("Picture-in-Picture Active", "画中画置顶运行中"), action: nil, keyEquivalent: "")
            pipTitle.isEnabled = false
            menu.addItem(pipTitle)

            if PinManager.shared.hasGhostWindows {
                let unghost = NSMenuItem(title: L10n.t("Disable Ghost Mode (Restore Clicks)", "关闭幽灵模式（恢复点击）"), action: #selector(disableGhostMode), keyEquivalent: "")
                unghost.target = self
                menu.addItem(unghost)
            }
            let closePip = NSMenuItem(title: L10n.t("Close All PiP Windows", "关闭全部画中画窗口"), action: #selector(closeAllPiP), keyEquivalent: "")
            closePip.target = self
            menu.addItem(closePip)
        }

        menu.addItem(.separator())

        // Display Style submenu
        let styleMenuItem = NSMenuItem(title: L10n.t("Display Mode", "显示模式"), action: nil, keyEquivalent: "")
        let styleSubmenu = NSMenu()
        let fullItem = NSMenuItem(title: DisplayStyle.full.title, action: #selector(setDisplayStyleFull), keyEquivalent: "")
        fullItem.target = self
        fullItem.state = DisplayStyle.current == .full ? .on : .off
        styleSubmenu.addItem(fullItem)

        let thumbOnlyItem = NSMenuItem(title: DisplayStyle.thumbnailsOnly.title, action: #selector(setDisplayStyleThumbnailsOnly), keyEquivalent: "")
        thumbOnlyItem.target = self
        thumbOnlyItem.state = DisplayStyle.current == .thumbnailsOnly ? .on : .off
        styleSubmenu.addItem(thumbOnlyItem)

        let iconsOnlyItem = NSMenuItem(title: DisplayStyle.iconsOnly.title, action: #selector(setDisplayStyleIconsOnly), keyEquivalent: "")
        iconsOnlyItem.target = self
        iconsOnlyItem.state = DisplayStyle.current == .iconsOnly ? .on : .off
        styleSubmenu.addItem(iconsOnlyItem)
        styleMenuItem.submenu = styleSubmenu
        menu.addItem(styleMenuItem)

        // Thumbnail Size submenu
        let sizeMenuItem = NSMenuItem(title: L10n.t("Thumbnail Size", "预览尺寸"), action: nil, keyEquivalent: "")
        let sizeSubmenu = NSMenu()
        let smallItem = NSMenuItem(title: ThumbnailSize.small.title, action: #selector(setThumbnailSizeSmall), keyEquivalent: "")
        smallItem.target = self
        smallItem.state = ThumbnailSize.current == .small ? .on : .off
        sizeSubmenu.addItem(smallItem)

        let mediumItem = NSMenuItem(title: ThumbnailSize.medium.title, action: #selector(setThumbnailSizeMedium), keyEquivalent: "")
        mediumItem.target = self
        mediumItem.state = ThumbnailSize.current == .medium ? .on : .off
        sizeSubmenu.addItem(mediumItem)

        let largeItem = NSMenuItem(title: ThumbnailSize.large.title, action: #selector(setThumbnailSizeLarge), keyEquivalent: "")
        largeItem.target = self
        largeItem.state = ThumbnailSize.current == .large ? .on : .off
        sizeSubmenu.addItem(largeItem)
        sizeMenuItem.submenu = sizeSubmenu
        menu.addItem(sizeMenuItem)

        let hintsItem = NSMenuItem(
            title: L10n.t("Show Shortcut Hints in Footer", "底部显示快捷键提示"),
            action: #selector(toggleShowFooterHints),
            keyEquivalent: ""
        )
        hintsItem.target = self
        hintsItem.state = AppearancePreferences.showFooterHints ? .on : .off
        menu.addItem(hintsItem)

        menu.addItem(.separator())

        let checkUpdates = NSMenuItem(
            title: L10n.t("Check for Updates…", "检查更新…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkUpdates.target = self
        menu.addItem(checkUpdates)

        let websiteItem = NSMenuItem(
            title: L10n.t("Official Website…", "访问官网…"),
            action: #selector(openWebsite),
            keyEquivalent: ""
        )
        websiteItem.target = self
        menu.addItem(websiteItem)

        let prefs = NSMenuItem(title: L10n.t("Preferences…", "设置…"), action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let relaunch = NSMenuItem(title: L10n.t("Relaunch AltDeck", "重启 AltDeck"), action: #selector(relaunch), keyEquivalent: "r")
        relaunch.target = self
        menu.addItem(relaunch)

        let quit = NSMenuItem(title: L10n.t("Quit AltDeck", "退出 AltDeck"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func permissionRow(label: String, granted: Bool, action: Selector) -> NSMenuItem {
        let stateText = granted ? L10n.t("On", "已开启") : L10n.t("Off", "未开启")
        let item = NSMenuItem(
            title: L10n.t("\(label): \(stateText)", "\(label)：\(stateText)"),
            action: granted ? nil : action,
            keyEquivalent: ""
        )
        item.target = granted ? nil : self
        item.image = NSImage(
            systemSymbolName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        item.image?.isTemplate = true
        return item
    }
}