import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let interceptor = HotKeyInterceptor()
    private lazy var controller = SwitcherController()
    private lazy var preferences = PreferencesWindowController()
    private var statusItem: NSStatusItem?
    private var didAskForPermissions = false

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.configure()
        didAskForPermissions = UserDefaults.standard.bool(forKey: "TabStation.didAskForPermissions")

        installStatusItem()
        installHotKeys()
        setupPreferencesHandlers()
        handlePermissions()
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
            // The tap could not be created: Accessibility is denied, so there is
            // no way to observe ⌥Tab at all. Say so loudly, once.
            showAccessibilityRequiredAlert()
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
    }

    // MARK: - Permissions

    private func handlePermissions() {
        let needsAccessibility = !Permissions.accessibilityGranted
        let needsScreenRecording = !Permissions.screenRecordingGranted

        if needsAccessibility || needsScreenRecording {
            if !didAskForPermissions {
                didAskForPermissions = true
                UserDefaults.standard.set(true, forKey: "TabStation.didAskForPermissions")
                if needsAccessibility {
                    Permissions.requestAccessibility()
                }
                if needsScreenRecording {
                    Permissions.requestScreenRecording()
                }
            }
            if needsAccessibility {
                showAccessibilityRequiredAlert()
            }
        }
    }

    private func showAccessibilityRequiredAlert() {
        // Silent: non-blocking, never pop up modal alerts to disrupt the user.
    }

    private var hasShownAlert = false

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "square.stack.3d.up.fill",
                accessibilityDescription: "TabStation"
            )
            button.image?.isTemplate = true
            button.toolTip = "TabStation — hold ⌥ and tap Tab"
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    // MARK: - Actions

    private func setupPreferencesHandlers() {
        preferences.onShortcutChange = { [weak self] role, shortcut in
            guard let self else { return }
            switch role {
            case .primary:
                self.interceptor.primaryShortcut = shortcut
                self.statusItem?.button?.toolTip = "TabStation — hold \(shortcut.displayString)"
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
        let current = UserDefaults.standard.bool(forKey: "TabStation.includeBrowserTabs")
        UserDefaults.standard.set(!current, forKey: "TabStation.includeBrowserTabs")
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
        if !Permissions.accessibilityGranted {
            Permissions.requestAccessibility()
        }
        if !Permissions.screenRecordingGranted {
            Permissions.requestScreenRecording()
        }
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

        let title = NSMenuItem(title: "TabStation", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        menu.addItem(permissionRow(
            label: "Accessibility",
            granted: accessibility,
            action: #selector(openAccessibilitySettings)
        ))
        menu.addItem(permissionRow(
            label: "Screen Recording",
            granted: screenRecording,
            action: #selector(openScreenRecordingSettings)
        ))

        if !accessibility || !screenRecording {
            menu.addItem(.separator())
            let request = NSMenuItem(
                title: "Request Permissions…",
                action: #selector(requestPermissions),
                keyEquivalent: ""
            )
            request.target = self
            menu.addItem(request)
        }

        menu.addItem(.separator())

        let shortcuts = NSMenuItem(
            title: "Hold \(ShortcutStore.load().displayString) to switch windows",
            action: nil,
            keyEquivalent: ""
        )
        shortcuts.isEnabled = false
        menu.addItem(shortcuts)

        menu.addItem(.separator())

        let overrideItem = NSMenuItem(
            title: "Override ⌘Tab",
            action: #selector(toggleOverrideCommandTab),
            keyEquivalent: ""
        )
        overrideItem.target = self
        overrideItem.state = UserDefaults.standard.bool(forKey: "TabStation.overrideCommandTab") ? .on : .off
        menu.addItem(overrideItem)

        let minItem = NSMenuItem(
            title: "Show Minimized Windows",
            action: #selector(toggleShowMinimized),
            keyEquivalent: ""
        )
        minItem.target = self
        minItem.state = UserDefaults.standard.bool(forKey: "TabStation.showMinimized") ? .on : .off
        menu.addItem(minItem)

        let includeTabsItem = NSMenuItem(
            title: "Include Browser Tabs",
            action: #selector(toggleIncludeBrowserTabs),
            keyEquivalent: ""
        )
        includeTabsItem.target = self
        includeTabsItem.state = UserDefaults.standard.bool(forKey: "TabStation.includeBrowserTabs") ? .on : .off
        menu.addItem(includeTabsItem)

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(loginItem)

        if PinManager.shared.hasPinnedWindows {
            menu.addItem(.separator())
            let pipTitle = NSMenuItem(title: "Picture-in-Picture Active", action: nil, keyEquivalent: "")
            pipTitle.isEnabled = false
            menu.addItem(pipTitle)

            if PinManager.shared.hasGhostWindows {
                let unghost = NSMenuItem(title: "Disable Ghost Mode (Restore Clicks)", action: #selector(disableGhostMode), keyEquivalent: "")
                unghost.target = self
                menu.addItem(unghost)
            }
            let closePip = NSMenuItem(title: "Close All PiP Windows", action: #selector(closeAllPiP), keyEquivalent: "")
            closePip.target = self
            menu.addItem(closePip)
        }

        menu.addItem(.separator())

        // Display Style submenu
        let styleMenuItem = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
        let styleSubmenu = NSMenu()
        let fullItem = NSMenuItem(title: "Thumbnails & Titles", action: #selector(setDisplayStyleFull), keyEquivalent: "")
        fullItem.target = self
        fullItem.state = DisplayStyle.current == .full ? .on : .off
        styleSubmenu.addItem(fullItem)

        let thumbOnlyItem = NSMenuItem(title: "Thumbnails Only", action: #selector(setDisplayStyleThumbnailsOnly), keyEquivalent: "")
        thumbOnlyItem.target = self
        thumbOnlyItem.state = DisplayStyle.current == .thumbnailsOnly ? .on : .off
        styleSubmenu.addItem(thumbOnlyItem)

        let iconsOnlyItem = NSMenuItem(title: "App Icons Only", action: #selector(setDisplayStyleIconsOnly), keyEquivalent: "")
        iconsOnlyItem.target = self
        iconsOnlyItem.state = DisplayStyle.current == .iconsOnly ? .on : .off
        styleSubmenu.addItem(iconsOnlyItem)
        styleMenuItem.submenu = styleSubmenu
        menu.addItem(styleMenuItem)

        // Thumbnail Size submenu
        let sizeMenuItem = NSMenuItem(title: "Thumbnail Size", action: nil, keyEquivalent: "")
        let sizeSubmenu = NSMenu()
        let smallItem = NSMenuItem(title: "Small", action: #selector(setThumbnailSizeSmall), keyEquivalent: "")
        smallItem.target = self
        smallItem.state = ThumbnailSize.current == .small ? .on : .off
        sizeSubmenu.addItem(smallItem)

        let mediumItem = NSMenuItem(title: "Medium", action: #selector(setThumbnailSizeMedium), keyEquivalent: "")
        mediumItem.target = self
        mediumItem.state = ThumbnailSize.current == .medium ? .on : .off
        sizeSubmenu.addItem(mediumItem)

        let largeItem = NSMenuItem(title: "Large", action: #selector(setThumbnailSizeLarge), keyEquivalent: "")
        largeItem.target = self
        largeItem.state = ThumbnailSize.current == .large ? .on : .off
        sizeSubmenu.addItem(largeItem)
        sizeMenuItem.submenu = sizeSubmenu
        menu.addItem(sizeMenuItem)

        let hintsItem = NSMenuItem(
            title: "Show Shortcut Hints in Footer",
            action: #selector(toggleShowFooterHints),
            keyEquivalent: ""
        )
        hintsItem.target = self
        hintsItem.state = AppearancePreferences.showFooterHints ? .on : .off
        menu.addItem(hintsItem)

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let relaunch = NSMenuItem(title: "Relaunch TabStation", action: #selector(relaunch), keyEquivalent: "r")
        relaunch.target = self
        menu.addItem(relaunch)

        let quit = NSMenuItem(title: "Quit TabStation", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func permissionRow(label: String, granted: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(
            title: "\(label): \(granted ? "On" : "Off")",
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