import AppKit

/// Drives the whole interaction: builds the window list, shows and hides the
/// panel, moves the selection, and commits to the chosen window.
final class SwitcherController {

    private let view = SwitcherView()
    private let panel = SwitcherPanel()
    private let quickLook = QuickLookPanel()

    private var allWindows: [WindowInfo] = []
    private var visibleWindows: [WindowInfo] = []
    private var transientBrowserTabs: [WindowInfo] = []
    private var selectedIndex = 0
    private var appFilterEnabled = false
    private var browserFilterEnabled = false
    private var frontAppPID: pid_t = 0

    /// Bumped on every presentation so in-flight thumbnail loads from a previous
    /// presentation can be discarded.
    private var generation = 0
    private var isAnimatingOut = false
    private var lastActiveAppPID: pid_t = 0

    private(set) var isVisible = false

    private var dwellPrewarmWorkItem: DispatchWorkItem?
    private var dwellShowWorkItem: DispatchWorkItem?
    private var transientNoticeWorkItem: DispatchWorkItem?
    private var quickLookPinnedBySpace = false
    private let dwellPrewarmDelay: TimeInterval = 0.12
    private let dwellShowDelay: TimeInterval = 0.36

    /// Upper bound on thumbnails fetched per presentation.
    private let maxConcurrentCaptures = 4

    init() {
        panel.contentView = view

        view.onActivate = { [weak self] index in
            self?.setSelection(index, animated: false)
            self?.commit()
        }
        view.onHover = { [weak self] index in
            self?.setSelection(index, animated: false)
        }
        view.onCloseWindow = { [weak self] index in
            self?.closeWindow(at: index)
        }
        view.onSnapLeft = { [weak self] index in
            guard let self, index >= 0, index < self.visibleWindows.count else { return }
            let target = self.visibleWindows[index]
            let activeScreen = self.screenUnderCursor()
            _ = WindowGridManager.snap(window: target, to: .leftHalf, targetScreen: activeScreen)
            self.hide(instant: true)
            WindowActivator.activate(target)
        }
        view.onSnapRight = { [weak self] index in
            guard let self, index >= 0, index < self.visibleWindows.count else { return }
            let target = self.visibleWindows[index]
            let activeScreen = self.screenUnderCursor()
            _ = WindowGridManager.snap(window: target, to: .rightHalf, targetScreen: activeScreen)
            self.hide(instant: true)
            WindowActivator.activate(target)
        }
        view.onSnapPopover = { [weak self] index, anchorView in
            guard let self, index >= 0, index < self.visibleWindows.count else { return }
            self.setSelection(index)
            let target = self.visibleWindows[index]
            let activeScreen = self.screenUnderCursor()
            WindowSnapPanel.shared.onSnapped = { [weak self] msg in
                self?.showTransientNotice(msg)
            }
            WindowSnapPanel.shared.show(for: target, relativeTo: anchorView, targetScreen: activeScreen)
        }
        view.onPinWindow = { [weak self] index in
            guard let self, index >= 0, index < self.visibleWindows.count else { return }
            self.setSelection(index)
            self.togglePinCurrent()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let myPID = ProcessInfo.processInfo.processIdentifier
            if app.processIdentifier != myPID && (app.activationPolicy == .regular || app.activationPolicy == .accessory) {
                self?.lastActiveAppPID = app.processIdentifier
            }
        }

        NotificationCenter.default.addObserver(
            forName: .tabStationAppearanceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            let screen = self.screenUnderCursor()
            self.panel.applyAppearancePreferences()
            self.configureView(on: screen)
            self.layoutPanel(on: screen)
            self.view.setSelection(self.selectedIndex, animated: false)
        }
    }

    // Callbacks for interceptor hold-modifier tracking
    var onSwitcherOpen: ((ActiveShortcutRole) -> Void)?
    var onSwitcherClose: (() -> Void)?

    // MARK: - Key handling

    func handle(_ key: SwitcherKey) {
        switch key {
        case .next:
            guard isVisible else {
                let scope = ShortcutScopeStore.load(.primary)
                if scope == .activeApp {
                    return presentFilteredByCurrentApp(role: .primary)
                } else {
                    return present(startingAt: 1)
                }
            }
            moveSelection(by: 1)

        case .previous:
            guard isVisible else {
                let scope = ShortcutScopeStore.load(.primary)
                if scope == .activeApp {
                    return presentFilteredByCurrentApp(role: .primary)
                } else {
                    return present(startingAt: -1)
                }
            }
            moveSelection(by: -1)

        case .sameAppNext:
            guard isVisible else {
                let scope = ShortcutScopeStore.load(.sameApp)
                if scope == .allApps {
                    return present(startingAt: 1)
                } else {
                    return presentFilteredByCurrentApp(role: .sameApp)
                }
            }
            if appFilterEnabled {
                moveSelection(by: 1)
            } else {
                cycleWithinCurrentApp(backwards: false)
            }

        case .sameAppPrevious:
            guard isVisible else {
                let scope = ShortcutScopeStore.load(.sameApp)
                if scope == .allApps {
                    return present(startingAt: -1)
                } else {
                    return presentFilteredByCurrentApp(role: .sameApp)
                }
            }
            if appFilterEnabled {
                moveSelection(by: -1)
            } else {
                cycleWithinCurrentApp(backwards: true)
            }

        case .closeWindow:
            guard isVisible else { return }
            closeSelectedWindow()

        case .minimizeWindow:
            guard isVisible else { return }
            minimizeSelectedWindow()

        case .quitApp:
            guard isVisible else { return }
            quitSelectedApp()

        case .quickLook:
            guard isVisible else { return }
            toggleQuickLook()

        case .moveToNextDisplay:
            guard isVisible else { return }
            moveCurrentToNextDisplay()

        case .pinOnTop:
            guard isVisible else { return }
            togglePinCurrent()

        case .toggleBrowserTabs:
            guard isVisible else { return }
            toggleBrowserTabsFilter()

        case .snapLeft:
            guard isVisible, selectedIndex >= 0, selectedIndex < visibleWindows.count else { return }
            let activeScreen = screenUnderCursor()
            let msg = WindowGridManager.cycleLeft(window: visibleWindows[selectedIndex], targetScreen: activeScreen)
            showTransientNotice(msg)

        case .snapRight:
            guard isVisible, selectedIndex >= 0, selectedIndex < visibleWindows.count else { return }
            let activeScreen = screenUnderCursor()
            let msg = WindowGridManager.cycleRight(window: visibleWindows[selectedIndex], targetScreen: activeScreen)
            showTransientNotice(msg)

        case .snapUp:
            guard isVisible, selectedIndex >= 0, selectedIndex < visibleWindows.count else { return }
            let activeScreen = screenUnderCursor()
            let msg = WindowGridManager.cycleUp(window: visibleWindows[selectedIndex], targetScreen: activeScreen)
            showTransientNotice(msg)

        case .snapDown:
            guard isVisible, selectedIndex >= 0, selectedIndex < visibleWindows.count else { return }
            let activeScreen = screenUnderCursor()
            let msg = WindowGridManager.cycleDown(window: visibleWindows[selectedIndex], targetScreen: activeScreen)
            showTransientNotice(msg)

        case .snapCenter:
            guard isVisible, selectedIndex >= 0, selectedIndex < visibleWindows.count else { return }
            let activeScreen = screenUnderCursor()
            let msg = WindowGridManager.snap(window: visibleWindows[selectedIndex], to: .center, targetScreen: activeScreen)
            showTransientNotice(msg)

        case .escape:
            if quickLook.isVisible {
                quickLookPinnedBySpace = false
                quickLook.hideAnimated()
                return
            }
            cancel()

        case .commit:
            commit()
        }
    }

    // MARK: - Presentation

    private func present(startingAt offset: Int) {
        guard buildWindowList(), !allWindows.isEmpty else { return }
        appFilterEnabled = false
        browserFilterEnabled = false
        transientBrowserTabs = []
        applyFilter()
        let index = offset < 0 ? max(0, visibleWindows.count - 1) : min(offset, visibleWindows.count - 1)
        show(initialSelection: index, role: .primary)
    }

    /// Jump straight into the current app's windows, showing strictly that app's windows.
    private func presentFilteredByCurrentApp(role: ActiveShortcutRole) {
        guard buildWindowList() else { return }

        let frontBundleID = NSRunningApplication(processIdentifier: frontAppPID)?.bundleIdentifier
        var appWindows = allWindows.filter {
            $0.pid == frontAppPID || (frontBundleID != nil && $0.bundleID == frontBundleID)
        }

        guard !appWindows.isEmpty else {
            NSSound.beep()
            return
        }

        // Accurately determine the active window of the front app via targeted AX query
        if appWindows.count > 1 {
            appWindows = WindowEnumerator.sortWindowsByAXOrder(pid: frontAppPID, windows: appWindows)
        }

        // Strictly show only the active app's windows. NEVER show all windows.
        appFilterEnabled = true
        browserFilterEnabled = false
        transientBrowserTabs = []
        visibleWindows = appWindows
        let initial = appWindows.count > 1 ? 1 : 0
        show(initialSelection: initial, role: role)
    }

    @discardableResult
    private func buildWindowList() -> Bool {
        let currentFrontApp = NSWorkspace.shared.frontmostApplication
        let currentFront = currentFrontApp?.processIdentifier ?? 0
        let myPID = ProcessInfo.processInfo.processIdentifier

        if currentFront != myPID && currentFront != 0 &&
            (currentFrontApp?.activationPolicy == .regular || currentFrontApp?.activationPolicy == .accessory) {
            frontAppPID = currentFront
            lastActiveAppPID = currentFront
        } else if lastActiveAppPID != 0 {
            frontAppPID = lastActiveAppPID
        } else {
            frontAppPID = currentFront
        }

        let snapshot = WindowListCache.shared.snapshot(frontPID: frontAppPID)
        allWindows = snapshot.windows

        return !allWindows.isEmpty
    }

    private func applyFilter() {
        if browserFilterEnabled {
            let indexed = allWindows.filter { $0.browserTab != nil }
            let tabs = transientBrowserTabs.isEmpty ? indexed : transientBrowserTabs
            visibleWindows = tabs.isEmpty ? allWindows : tabs
        } else if appFilterEnabled && frontAppPID != 0 {
            let frontBundleID = NSRunningApplication(processIdentifier: frontAppPID)?.bundleIdentifier
            let filtered = allWindows.filter {
                $0.pid == frontAppPID || (frontBundleID != nil && $0.bundleID == frontBundleID)
            }
            visibleWindows = filtered
        } else {
            visibleWindows = allWindows
        }
        if selectedIndex >= visibleWindows.count {
            selectedIndex = max(0, visibleWindows.count - 1)
        }
    }

    private var outsideClickMonitor: Any?

    private func show(initialSelection: Int, role: ActiveShortcutRole) {
        let screen = screenUnderCursor()
        selectedIndex = min(max(0, initialSelection), max(0, visibleWindows.count - 1))

        panel.applyAppearancePreferences()
        configureView(on: screen)

        layoutPanel(on: screen)
        // Instant presentation with 0ms fade-in delay, matching Apple native Command-Tab
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        isVisible = true
        isAnimatingOut = false
        onSwitcherOpen?(role)
        startOutsideClickMonitoring()

        view.setSelection(selectedIndex, animated: false)
        scheduleDwellPreview()
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.isVisible else { return }
            let mouse = NSEvent.mouseLocation
            if !self.panel.frame.contains(mouse) {
                DispatchQueue.main.async {
                    self.cancel()
                }
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    /// Rebuilds the grid and kicks off thumbnail loading. Shared by `show`
    /// and filter/action updates.
    private func configureView(on screen: NSScreen) {
        view.hints = makeHints()
        view.configure(
            items: makeItems(),
            availableHeight: screen.visibleFrame.height,
            availableWidth: screen.visibleFrame.width,
            notice: makeNotice(),
            style: DisplayStyle.current,
            size: ThumbnailSize.current
        )
        loadThumbnails()
    }

    /// Legend for the panel footer, derived from the live shortcuts and enabled features.
    private func makeHints() -> [String] {
        let all = ShortcutStore.loadAll()
        let p = all[.primary] ?? .optionTab
        let s = all[.sameApp] ?? Shortcut(modifiers: [.option], keyCode: KeyCode.grave)
        let activeKey = appFilterEnabled ? s.displayString : p.displayString
        var list = ["\(activeKey) next"]
        if FeaturePreferences.spaceQuickLookEnabled {
            list.append("space peek")
        }
        list.append(FeaturePreferences.arrowKeySnappingEnabled ? "←/→ snap" : "←/→ select")
        if FeaturePreferences.pinShortcutEnabled {
            list.append("P pin")
        }
        if FeaturePreferences.displayMoveShortcutEnabled {
            list.append("D display")
        }
        if FeaturePreferences.browserTabsShortcutEnabled {
            list.append("S tabs")
        }
        list.append("W close")
        return list
    }

    /// Sizes and centres the panel over the screen under the cursor. Must run
    /// after `view.configure`, since the panel's width depends on the items.
    private func layoutPanel(on screen: NSScreen) {
        let size = view.preferredSize(for: screen)
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size, on: screen))
    }

    private func makeItems() -> [SwitcherItem] {
        // Number each window within its app so the caption stays meaningful
        // even when window titles are unavailable (no Screen Recording).
        var counters: [pid_t: (index: Int, total: Int)] = [:]
        var totals: [pid_t: Int] = [:]
        for window in visibleWindows {
            totals[window.pid, default: 0] += 1
        }

        return visibleWindows.map { window in
            let current = counters[window.pid]?.index ?? 0
            counters[window.pid] = (index: current + 1, total: totals[window.pid] ?? 1)
            return SwitcherItem(
                window: window,
                caption: window.caption(windowNumber: current + 1, windowCount: totals[window.pid] ?? 1),
                icon: IconCache.shared.icon(bundleID: window.bundleID, pid: window.pid)
            )
        }
    }

    private func makeNotice() -> [String] {
        return []
    }

    // MARK: - Selection

    private func setSelection(_ index: Int, animated: Bool = true) {
        guard index >= 0, index < visibleWindows.count else { return }
        guard index != selectedIndex else { return }
        selectedIndex = index
        view.setSelection(index, animated: animated)
        cancelDwellPreview()
        if quickLook.isVisible && quickLookPinnedBySpace {
            let screen = screenUnderCursor()
            quickLook.update(
                for: visibleWindows[selectedIndex],
                on: screen,
                anchorRect: view.selectedCellScreenRect(),
                switcherFrame: panel.frame
            )
        } else {
            if quickLook.isVisible {
                quickLook.hideImmediately()
            }
            scheduleDwellPreview()
        }
    }

    private func scheduleDwellPreview() {
        cancelDwellPreview()
        guard DisplayStyle.current == .iconsOnly,
              AppearancePreferences.autoPreviewOnHold,
              selectedIndex >= 0, selectedIndex < visibleWindows.count else { return }

        let target = visibleWindows[selectedIndex]
        let screen = screenUnderCursor()

        // Silently capture preview frame after a short pause so display is instant at dwellShowDelay
        let prewarmWork = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible, !self.isAnimatingOut,
                  self.selectedIndex >= 0, self.selectedIndex < self.visibleWindows.count,
                  self.visibleWindows[self.selectedIndex].id == target.id else { return }
            self.quickLook.prewarm(for: target, on: screen)
        }
        dwellPrewarmWorkItem = prewarmWork
        DispatchQueue.main.asyncAfter(deadline: .now() + dwellPrewarmDelay, execute: prewarmWork)

        let showWork = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible, !self.isAnimatingOut,
                  DisplayStyle.current == .iconsOnly,
                  AppearancePreferences.autoPreviewOnHold,
                  self.selectedIndex >= 0, self.selectedIndex < self.visibleWindows.count,
                  self.visibleWindows[self.selectedIndex].id == target.id else { return }
            let liveScreen = self.screenUnderCursor()
            self.quickLook.show(
                for: target,
                on: liveScreen,
                anchorRect: self.view.selectedCellScreenRect(),
                switcherFrame: self.panel.frame
            )
        }
        dwellShowWorkItem = showWork
        DispatchQueue.main.asyncAfter(deadline: .now() + dwellShowDelay, execute: showWork)
    }

    private func cancelDwellPreview() {
        dwellPrewarmWorkItem?.cancel()
        dwellPrewarmWorkItem = nil
        dwellShowWorkItem?.cancel()
        dwellShowWorkItem = nil
    }

    private func moveSelection(by delta: Int) {
        guard !visibleWindows.isEmpty else { return }
        let count = visibleWindows.count
        let next = ((selectedIndex + delta) % count + count) % count
        setSelection(next)
    }

    /// ⌥` — move to the next window *of the same app as the current selection*,
    /// wrapping inside that app's block of the list. If only 1 window of that app exists,
    /// falls back to cycling across all windows so Tab never stalls or ignores keystrokes.
    private func cycleWithinCurrentApp(backwards: Bool) {
        guard !visibleWindows.isEmpty else { return }
        let currentApp = visibleWindows[selectedIndex].pid
        let indices = visibleWindows.indices.filter { visibleWindows[$0].pid == currentApp }
        if indices.count > 1, let position = indices.firstIndex(of: selectedIndex) {
            let step = backwards ? -1 : 1
            let next = ((position + step) % indices.count + indices.count) % indices.count
            setSelection(indices[next])
        } else {
            moveSelection(by: backwards ? -1 : 1)
        }
    }

    // MARK: - Window actions

    private func closeSelectedWindow() {
        closeWindow(at: selectedIndex)
    }

    private func closeWindow(at index: Int) {
        guard index >= 0, index < visibleWindows.count else { return }
        let target = visibleWindows[index]
        WindowActivator.close(target)

        allWindows.removeAll(where: { $0.id == target.id })
        visibleWindows.remove(at: index)

        if visibleWindows.isEmpty {
            cancel()
            return
        }

        selectedIndex = min(selectedIndex, visibleWindows.count - 1)
        let screen = screenUnderCursor()
        configureView(on: screen)
        layoutPanel(on: screen)
        view.setSelection(selectedIndex, animated: false)
    }

    private func minimizeSelectedWindow() {
        guard selectedIndex >= 0, selectedIndex < visibleWindows.count else { return }
        let target = visibleWindows[selectedIndex]
        WindowActivator.minimize(target)

        // If not showing minimized windows in switcher, remove from strip
        if !UserDefaults.standard.bool(forKey: "TabStation.showMinimized") {
            allWindows.removeAll(where: { $0.id == target.id })
            visibleWindows.remove(at: selectedIndex)
            if visibleWindows.isEmpty {
                cancel()
                return
            }
            selectedIndex = min(selectedIndex, visibleWindows.count - 1)
        }
        let screen = screenUnderCursor()
        configureView(on: screen)
        layoutPanel(on: screen)
        view.setSelection(selectedIndex, animated: false)
    }

    private func quitSelectedApp() {
        guard selectedIndex >= 0, selectedIndex < visibleWindows.count else { return }
        let pid = visibleWindows[selectedIndex].pid
        WindowActivator.quitApp(pid: pid)

        allWindows.removeAll(where: { $0.pid == pid })
        visibleWindows.removeAll(where: { $0.pid == pid })

        if visibleWindows.isEmpty {
            cancel()
            return
        }

        selectedIndex = min(selectedIndex, visibleWindows.count - 1)
        let screen = screenUnderCursor()
        configureView(on: screen)
        layoutPanel(on: screen)
        view.setSelection(selectedIndex, animated: false)
    }

    // MARK: - Commit / cancel

    private func commit() {
        guard isVisible, !isAnimatingOut else { return }
        guard selectedIndex >= 0, selectedIndex < visibleWindows.count else { return cancel() }
        let target = visibleWindows[selectedIndex]
        let activeScreen = screenUnderCursor()
        hide(instant: true)

        // 1. Immediately activate and focus the chosen window with 0ms latency
        WindowActivator.activate(target)

        // 2. If multi-monitor summon is enabled, move the window to active monitor
        let followActive = GeneralPreferences.followActiveDisplay
        if followActive && NSScreen.screens.count > 1 {
            let winScreen = WindowGridManager.screenContaining(window: target)
            if winScreen != activeScreen {
                DisplayDispatcher.move(window: target, to: activeScreen)
            }
        }
    }

    /// Immediately strips the HUD window from WindowServer on modifier release (< 1ms)
    /// while leaving state intact for `commit()` right after on the main queue.
    func hidePanelImmediately() {
        cancelDwellPreview()
        transientNoticeWorkItem?.cancel()
        transientNoticeWorkItem = nil
        quickLookPinnedBySpace = false
        guard isVisible, !isAnimatingOut else { return }
        WindowSnapPanel.shared.closeAnimated()
        quickLook.hideImmediately()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.orderOut(nil)
        CATransaction.commit()
        CATransaction.flush()
    }

    func cancel() {
        guard isVisible else { return }
        hide(instant: true)
    }

    private func hide(instant: Bool = true) {
        cancelDwellPreview()
        transientNoticeWorkItem?.cancel()
        transientNoticeWorkItem = nil
        quickLookPinnedBySpace = false
        stopOutsideClickMonitoring()
        WindowSnapPanel.shared.closeAnimated()
        if instant || DisplayStyle.current == .iconsOnly {
            quickLook.hideImmediately()
        } else if quickLook.isVisible {
            quickLook.hideAnimated()
        }

        isAnimatingOut = true
        isVisible = false
        appFilterEnabled = false
        browserFilterEnabled = false
        transientBrowserTabs = []

        if instant || DisplayStyle.current == .iconsOnly {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            panel.orderOut(nil)
            CATransaction.commit()
            CATransaction.flush()
            isAnimatingOut = false
            generation += 1  // abandon in-flight captures
            onSwitcherClose?()
            WindowListCache.shared.invalidateAndPrewarm()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.hide
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.isAnimatingOut = false
            self.generation += 1  // abandon in-flight captures
            self.onSwitcherClose?()
            WindowListCache.shared.invalidateAndPrewarm()
        })
    }

    // MARK: - Workstation Actions

    private func toggleQuickLook() {
        guard FeaturePreferences.spaceQuickLookEnabled else { return }
        cancelDwellPreview()
        guard selectedIndex >= 0, selectedIndex < visibleWindows.count else { return }
        let target = visibleWindows[selectedIndex]
        quickLookPinnedBySpace = !quickLook.isVisible
        quickLook.toggle(
            for: target,
            on: screenUnderCursor(),
            anchorRect: view.selectedCellScreenRect(),
            switcherFrame: panel.frame
        )
    }

    private func moveCurrentToNextDisplay() {
        guard selectedIndex >= 0, selectedIndex < visibleWindows.count else { return }
        let target = visibleWindows[selectedIndex]
        let msg = DisplayDispatcher.moveToNextDisplay(window: target)
        showTransientNotice(msg)
        if quickLook.isVisible {
            quickLook.update(
                for: target,
                on: screenUnderCursor(),
                anchorRect: view.selectedCellScreenRect(),
                switcherFrame: panel.frame
            )
        }
    }

    private func togglePinCurrent() {
        guard selectedIndex >= 0, selectedIndex < visibleWindows.count else { return }
        let target = visibleWindows[selectedIndex]
        let res = PinManager.shared.togglePin(for: target, on: screenUnderCursor())
        showTransientNotice(res.message)
    }

    private func toggleBrowserTabsFilter() {
        guard FeaturePreferences.browserTabsShortcutEnabled else { return }

        if browserFilterEnabled {
            browserFilterEnabled = false
            transientBrowserTabs = []
            applyFilter()
            let screen = screenUnderCursor()
            configureView(on: screen)
            layoutPanel(on: screen)
            selectedIndex = min(selectedIndex, max(0, visibleWindows.count - 1))
            view.setSelection(selectedIndex, animated: false)
            showTransientNotice("Showing all windows")
            return
        }

        browserFilterEnabled = true
        let existingTabs = allWindows.filter { $0.browserTab != nil }
        let cached = existingTabs.isEmpty ? WindowListCache.shared.cachedBrowserTabsSnapshot() : existingTabs
        if !cached.isEmpty {
            transientBrowserTabs = cached
            applyFilter()
            let screen = screenUnderCursor()
            configureView(on: screen)
            layoutPanel(on: screen)
            selectedIndex = 0
            view.setSelection(0, animated: false)
            showTransientNotice("Browser Tabs (\(cached.count)) — S to exit")
        } else {
            showTransientNotice("Loading browser tabs…")
        }

        let currentGen = generation
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let fetchResult = BrowserTabService.shared.fetchTabsResult(promptIfNeeded: true)
            let freshTabs = fetchResult.tabs
            WindowListCache.shared.updateCachedBrowserTabs(freshTabs)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isVisible, self.browserFilterEnabled, self.generation == currentGen else { return }
                guard !freshTabs.isEmpty else {
                    self.browserFilterEnabled = false
                    self.transientBrowserTabs = []
                    self.applyFilter()
                    let screen = self.screenUnderCursor()
                    self.configureView(on: screen)
                    self.layoutPanel(on: screen)
                    self.selectedIndex = min(self.selectedIndex, max(0, self.visibleWindows.count - 1))
                    self.view.setSelection(self.selectedIndex, animated: false)
                    if !fetchResult.deniedBrowsers.isEmpty {
                        let names = fetchResult.deniedBrowsers.joined(separator: ", ")
                        self.showTransientNotice("Allow Automation for \(names) in Privacy Settings")
                    } else {
                        self.showTransientNotice("No open browser tabs found")
                    }
                    return
                }
                self.transientBrowserTabs = freshTabs
                if !self.browserTabsEqual(cached, freshTabs) {
                    self.applyFilter()
                    let screen = self.screenUnderCursor()
                    self.configureView(on: screen)
                    self.layoutPanel(on: screen)
                    self.selectedIndex = min(self.selectedIndex, max(0, freshTabs.count - 1))
                    self.view.setSelection(self.selectedIndex, animated: false)
                    self.showTransientNotice("Browser Tabs (\(freshTabs.count)) — S to exit")
                }
            }
        }
    }

    private func browserTabsEqual(_ lhs: [WindowInfo], _ rhs: [WindowInfo]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (a, b) in zip(lhs, rhs) {
            if a.id != b.id || a.title != b.title || a.browserTab?.url != b.browserTab?.url {
                return false
            }
        }
        return true
    }

    private func showTransientNotice(_ text: String) {
        transientNoticeWorkItem?.cancel()
        setNotices([text])
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible else { return }
            self.setNotices(self.makeNotice())
        }
        transientNoticeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func setNotices(_ list: [String]) {
        view.notices = list
        guard isVisible else { return }
        layoutPanel(on: screenUnderCursor())
        view.layoutSubtreeIfNeeded()
    }

    // MARK: - Screens

    private func screenUnderCursor() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
            ?? NSScreen()
    }

    private func origin(for size: CGSize, on screen: NSScreen) -> NSPoint {
        let frame = screen.visibleFrame
        // Slightly above centre, so it doesn't cover the thing you're switching to.
        let x = frame.midX - size.width / 2
        let y = frame.midY - size.height / 2 + size.height * 0.08
        return NSPoint(x: x.rounded(), y: y.rounded())
    }

    // MARK: - Thumbnails

    private func loadThumbnails() {
        guard Permissions.screenRecordingGranted, DisplayStyle.current != .iconsOnly else {
            return
        }

        generation += 1
        let gen = generation
        let metrics = view.thumbnailMetrics
        var targets: [(id: CGWindowID, size: CGSize)] = []
        for window in visibleWindows {
            if window.browserTab != nil {
                view.applyThumbnail(nil, toWindowID: window.id)
                continue
            }
            let width = min(metrics.maxWidth, max(metrics.minWidth, (metrics.height * window.aspectRatio).rounded()))
            // 2x so thumbnails stay crisp on Retina displays.
            let size = CGSize(width: width * 2, height: metrics.height * 2)
            targets.append((id: window.id, size: size))
        }
        guard !targets.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            let service = ThumbnailService.shared

            for chunk in targets.chunked(into: maxConcurrentCaptures) {
                guard gen == generation else { return }
                await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
                    for target in chunk {
                        group.addTask {
                            let image = await service.thumbnail(windowID: target.id, pixelSize: target.size)
                            return (target.id, image.map { NSImage(cgImage: $0, size: .zero) })
                        }
                    }
                    for await (id, image) in group {
                        guard gen == self.generation else { return }
                        await MainActor.run { self.view.applyThumbnail(image, toWindowID: id) }
                    }
                }
            }
        }
    }
}

// MARK: - Small helpers

extension Array {
    /// Fixed-size batches, used to bound how many screenshots we ask
    /// ScreenCaptureKit for at once.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}