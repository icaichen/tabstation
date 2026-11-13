import AppKit
import CoreGraphics

/// Fast in-memory cache for application icons to avoid expensive disk I/O on hotkey press.
final class IconCache: @unchecked Sendable {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private var pidCache: [pid_t: NSImage] = [:]
    private let lock = NSLock()

    func icon(bundleID: String?, pid: pid_t) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let bundleID, let img = cache[bundleID] {
            return img
        }
        if let img = pidCache[pid] {
            return img
        }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        if let icon = app.icon {
            if let bId = app.bundleIdentifier ?? bundleID {
                cache[bId] = icon
            }
            pidCache[pid] = icon
            return icon
        }
        return nil
    }

    func purge(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        pidCache.removeValue(forKey: pid)
    }
}

/// Thread-safe window list cache with proactive pre-warming.
/// Ensures pressing hotkeys yields <1ms instant presentation with zero blocking AppleScript or AX IPC.
final class WindowListCache: @unchecked Sendable {
    static let shared = WindowListCache()

    private var cachedSnapshot: WindowEnumerator.Snapshot?
    private var cachedMinimized: [WindowInfo] = []
    private var cachedBrowserTabs: [WindowInfo] = []
    private var cachedAccessorySubroles: [pid_t: [CGWindowID: String]] = [:]
    private var cachedAXTitles: [CGWindowID: String] = [:]
    private var lastRefreshUptime: TimeInterval = 0
    private var lastSlowRefreshUptime: TimeInterval = 0
    private let lock = NSLock()
    private var isRefreshing = false
    private var periodicTimer: DispatchSourceTimer?

    private init() {
        setupObservers()
        startPeriodicPrewarm()
        invalidateAndPrewarm()
    }

    private func setupObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        let notifs: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ]
        for notif in notifs {
            ws.addObserver(forName: notif, object: nil, queue: nil) { [weak self] note in
                if notif == NSWorkspace.didActivateApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    MRUTracker.shared.recordFrontmostAppWindow(pid: app.processIdentifier)
                }
                self?.invalidateAndPrewarm()
            }
        }
    }

    private func startPeriodicPrewarm() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.refreshInBackground()
        }
        timer.resume()
        periodicTimer = timer
    }

    func cachedBrowserTabsSnapshot() -> [WindowInfo] {
        lock.lock()
        defer { lock.unlock() }
        return cachedBrowserTabs
    }

    func updateCachedBrowserTabs(_ tabs: [WindowInfo]) {
        lock.lock()
        cachedBrowserTabs = tabs
        lock.unlock()
    }

    func invalidateAndPrewarm() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.refreshInBackground()
        }
    }

    func snapshot(frontPID: pid_t) -> WindowEnumerator.Snapshot {
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        let age = now - lastRefreshUptime
        // Serve warm cache immediately (< 0.2ms). Trigger async background refresh if > 0.35s old.
        if age < 3.0, let cached = cachedSnapshot, !cached.isEmpty {
            var snap = cached
            lock.unlock()
            if frontPID != 0, let firstPID = snap.windows.first?.pid, firstPID != frontPID {
                snap.windows = WindowEnumerator.reorderWindows(snap.windows, frontPID: frontPID)
            }
            if age > 0.35 {
                invalidateAndPrewarm()
            }
            return snap
        }
        let currentMinimized = cachedMinimized
        let currentTabs = cachedBrowserTabs
        let currentSubroles = cachedAccessorySubroles
        let currentTitles = cachedAXTitles
        lock.unlock()

        // Cold cache fallback: pure WindowServer read + cached metadata (~3-8ms), NEVER synchronous AppleScript/AX.
        let snap = WindowEnumerator.snapshotDirect(
            cachedMinimized: currentMinimized,
            cachedBrowserTabs: currentTabs,
            cachedAccessorySubroles: currentSubroles,
            cachedAXTitles: currentTitles,
            frontPID: frontPID
        )

        lock.lock()
        self.cachedSnapshot = snap
        self.lastRefreshUptime = now
        lock.unlock()

        invalidateAndPrewarm()
        return snap
    }

    private func refreshInBackground() {
        lock.lock()
        if isRefreshing {
            lock.unlock()
            return
        }
        isRefreshing = true
        let existingTabs = cachedBrowserTabs
        let existingMin = cachedMinimized
        let lastSlow = lastSlowRefreshUptime
        lock.unlock()

        let now = ProcessInfo.processInfo.systemUptime
        let runSlowIPC = (now - lastSlow) >= 2.0

        var minWindows = existingMin
        if UserDefaults.standard.bool(forKey: "TabStation.showMinimized") && Permissions.accessibilityGranted {
            if runSlowIPC || minWindows.isEmpty {
                minWindows = WindowEnumerator.findMinimizedWindowsBackground()
            }
        } else {
            minWindows = []
        }

        var browserTabs = existingTabs
        if FeaturePreferences.includeBrowserTabsByDefault || FeaturePreferences.browserTabsShortcutEnabled {
            if runSlowIPC || browserTabs.isEmpty {
                browserTabs = BrowserTabService.shared.fetchTabs()
            }
        } else {
            browserTabs = []
        }

        let axData = WindowEnumerator.fetchBackgroundAXMetadata(allowTitleQueries: runSlowIPC)
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let snap = WindowEnumerator.snapshotDirect(
            cachedMinimized: minWindows,
            cachedBrowserTabs: browserTabs,
            cachedAccessorySubroles: axData.subroles,
            cachedAXTitles: axData.titles,
            frontPID: frontPID,
            allowFrontAXQuery: true
        )

        // Pre-warm app icons off the main thread
        for item in snap.windows {
            _ = IconCache.shared.icon(bundleID: item.bundleID, pid: item.pid)
        }

        if DisplayStyle.current != .iconsOnly && Permissions.screenRecordingGranted {
            Task.detached(priority: .utility) {
                await ThumbnailService.shared.refresh()
            }
        }

        lock.lock()
        self.cachedMinimized = minWindows
        self.cachedBrowserTabs = browserTabs
        self.cachedAccessorySubroles = axData.subroles
        self.cachedAXTitles = axData.titles
        self.cachedSnapshot = snap
        self.lastRefreshUptime = ProcessInfo.processInfo.systemUptime
        if runSlowIPC {
            self.lastSlowRefreshUptime = self.lastRefreshUptime
        }
        self.isRefreshing = false
        lock.unlock()
    }
}

/// Reads the list of on-screen windows straight from the window server.
enum WindowEnumerator {

    struct Snapshot {
        var windows: [WindowInfo] = []
        /// False when the window server redacted titles (no Screen Recording).
        var titlesAvailable = false

        var isEmpty: Bool { windows.isEmpty }
    }

    private struct AppInfo {
        let bundleID: String?
        let name: String
        let app: NSRunningApplication?
    }

    /// Primary entry point: returns a fast/cached snapshot.
    static func snapshot(excluding pid: pid_t = ProcessInfo.processInfo.processIdentifier) -> Snapshot {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        return WindowListCache.shared.snapshot(frontPID: frontPID)
    }

    /// Fast on-screen window enumeration using WindowServer + pre-cached IPC metadata (no blocking IPC).
    static func snapshotDirect(
        excluding pid: pid_t = ProcessInfo.processInfo.processIdentifier,
        cachedMinimized: [WindowInfo] = [],
        cachedBrowserTabs: [WindowInfo] = [],
        cachedAccessorySubroles: [pid_t: [CGWindowID: String]] = [:],
        cachedAXTitles: [CGWindowID: String] = [:],
        frontPID: pid_t = 0,
        allowFrontAXQuery: Bool = false
    ) -> Snapshot {
        let showAllSpaces = UserDefaults.standard.object(forKey: "TabStation.showAllSpaces") as? Bool ?? true
        let options: CGWindowListOption = (showAllSpaces && SkyLightSpaces.isAvailable)
            ? [.excludeDesktopElements]
            : [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return Snapshot()
        }

        let activeSpaces = SkyLightSpaces.activeSpaceIDs()
        var snapshot = Snapshot()
        var frontToBack: [WindowInfo] = []
        var appInfoCache: [pid_t: AppInfo] = [:]

        for entry in raw {
            guard let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else { continue }
            guard let windowID = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            guard let ownerPID = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID != pid else { continue }
            guard let ownerName = entry[kCGWindowOwnerName as String] as? String, !ownerName.isEmpty else { continue }
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            guard bounds.width >= 100, bounds.height >= 100 else { continue }

            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.1 else { continue }

            let cached: AppInfo
            if let existing = appInfoCache[ownerPID] {
                cached = existing
            } else {
                let app = NSRunningApplication(processIdentifier: ownerPID)
                cached = AppInfo(bundleID: app?.bundleIdentifier, name: ownerName, app: app)
                appInfoCache[ownerPID] = cached
            }

            guard let app = cached.app, !app.isTerminated,
                  app.activationPolicy == .regular || app.activationPolicy == .accessory else { continue }
            if WindowQuirksFilter.shouldIgnoreApp(bundleID: cached.bundleID) { continue }

            let isOnScreen = (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false

            // For .accessory (LSUIElement) apps, only surface real standard/dialog windows —
            // never tiny popovers, menu bar extra panels, or background helpers.
            if app.activationPolicy == .accessory {
                guard bounds.width >= 200, bounds.height >= 150 else { continue }
                if let map = cachedAccessorySubroles[ownerPID], !map.isEmpty {
                    guard let subrole = map[windowID],
                          subrole == (kAXStandardWindowSubrole as String) || subrole == (kAXDialogSubrole as String) else {
                        continue
                    }
                } else {
                    guard isOnScreen else { continue }
                }
            }

            let rawTitle = (entry[kCGWindowName as String] as? String) ?? ""
            var title = rawTitle
            if title.isEmpty, let cachedTitle = cachedAXTitles[windowID] {
                title = cachedTitle
            }

            let spaces = SkyLightSpaces.spaces(for: windowID)
            let onActiveSpace = spaces.map { !activeSpaces.isDisjoint(with: $0) } ?? isOnScreen
            if !showAllSpaces && !onActiveSpace { continue }

            if WindowQuirksFilter.isGhostWindow(
                bundleID: cached.bundleID,
                ownerName: cached.name,
                title: title,
                bounds: bounds,
                isOnScreen: isOnScreen,
                onActiveSpace: onActiveSpace,
                isAppHidden: app.isHidden,
                spaces: spaces
            ) {
                continue
            }

            if !title.isEmpty { snapshot.titlesAvailable = true }

            frontToBack.append(
                WindowInfo(
                    id: windowID,
                    pid: ownerPID,
                    ownerName: cached.name,
                    bundleID: cached.bundleID,
                    title: title,
                    bounds: bounds,
                    isOnActiveSpace: onActiveSpace
                )
            )
        }

        let existingIDs = Set(frontToBack.map { $0.id })
        if UserDefaults.standard.bool(forKey: "TabStation.showMinimized") && !cachedMinimized.isEmpty {
            let filteredMin = cachedMinimized.filter { !existingIDs.contains($0.id) }
            frontToBack.append(contentsOf: filteredMin)
        }

        if FeaturePreferences.includeBrowserTabsByDefault && !cachedBrowserTabs.isEmpty {
            frontToBack.append(contentsOf: cachedBrowserTabs)
        }

        // Ensure running .regular Dock apps whose windows were closed/ordered out
        // (e.g. closed-to-tray WeChat, Finder, Terminal, custom apps) remain switchable
        // and reopenable via LaunchServices.
        let representedPIDs = Set(frontToBack.map { $0.pid })
        for app in NSWorkspace.shared.runningApplications {
            let appPID = app.processIdentifier
            guard appPID != pid,
                  !app.isTerminated,
                  app.activationPolicy == .regular,
                  !representedPIDs.contains(appPID),
                  !WindowQuirksFilter.shouldIgnoreApp(bundleID: app.bundleIdentifier) else { continue }
            let name = app.localizedName ?? ""
            guard !name.isEmpty else { continue }
            frontToBack.append(WindowInfo(
                id: 0,
                pid: appPID,
                ownerName: name,
                bundleID: app.bundleIdentifier,
                title: "",
                bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                isMinimized: false,
                isOnActiveSpace: true
            ))
        }

        snapshot.windows = groupByApp(frontToBack, frontPID: frontPID, allowFrontAXQuery: allowFrontAXQuery)
        return snapshot
    }

    /// Background scanner for minimized windows. Runs strictly off the main thread.
    static func findMinimizedWindowsBackground() -> [WindowInfo] {
        guard Permissions.accessibilityGranted else { return [] }
        var result: [WindowInfo] = []
        let myPID = ProcessInfo.processInfo.processIdentifier

        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != myPID
                && ($0.activationPolicy == .regular || $0.activationPolicy == .accessory)
                && !$0.isTerminated
                && !WindowQuirksFilter.shouldIgnoreApp(bundleID: $0.bundleIdentifier)
        }

        for app in apps {
            let appPID = app.processIdentifier
            let axApp = AXUIElementCreateApplication(appPID)
            var val: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &val) == .success,
                  let windows = val as? [AXUIElement] else { continue }

            for axWin in windows {
                var minVal: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axWin, kAXMinimizedAttribute as CFString, &minVal) == .success,
                      (minVal as? NSNumber)?.boolValue == true else { continue }

                var winID: CGWindowID = 0
                guard _AXUIElementGetWindow(axWin, &winID) == .success, winID > 0 else { continue }

                if app.activationPolicy == .accessory {
                    var subroleVal: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(axWin, kAXSubroleAttribute as CFString, &subroleVal)
                    let subrole = subroleVal as? String ?? ""
                    guard subrole == (kAXStandardWindowSubrole as String) || subrole == (kAXDialogSubrole as String) else {
                        continue
                    }
                }

                var titleVal: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleVal)
                let title = (titleVal as? String) ?? ""

                result.append(WindowInfo(
                    id: winID,
                    pid: appPID,
                    ownerName: app.localizedName ?? "",
                    bundleID: app.bundleIdentifier,
                    title: title,
                    bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                    isMinimized: true
                ))
            }
        }
        return result
    }

    static func reorderWindows(_ windows: [WindowInfo], frontPID: pid_t) -> [WindowInfo] {
        guard frontPID != 0 else { return windows }
        let frontWindows = windows.filter { $0.pid == frontPID }
        guard !frontWindows.isEmpty else { return windows }
        let otherWindows = windows.filter { $0.pid != frontPID }
        return frontWindows + otherWindows
    }

    private static func groupByApp(_ list: [WindowInfo], frontPID: pid_t, allowFrontAXQuery: Bool) -> [WindowInfo] {
        var order: [pid_t] = []
        var buckets: [pid_t: [WindowInfo]] = [:]
        for window in list {
            if buckets[window.pid] == nil {
                order.append(window.pid)
                buckets[window.pid] = []
            }
            buckets[window.pid]?.append(window)
        }

        if frontPID != 0, let idx = order.firstIndex(of: frontPID), idx > 0 {
            order.remove(at: idx)
            order.insert(frontPID, at: 0)
        }

        return order.flatMap { pid in
            let windows = buckets[pid] ?? []
            if allowFrontAXQuery && pid == frontPID && windows.count > 1 {
                return sortWindowsByAXOrder(pid: pid, windows: windows)
            }
            if windows.count > 1 {
                return windows.sorted { w1, w2 in
                    let r1 = MRUTracker.shared.rank(for: w1.id)
                    let r2 = MRUTracker.shared.rank(for: w2.id)
                    if r1 != r2 { return r1 > r2 }
                    return false
                }
            }
            return windows
        }
    }

    /// Sorts an application's windows by their true Accessibility z-order (front-to-back),
    /// which accurately reflects which window is currently focused / in front.
    static func sortWindowsByAXOrder(pid: pid_t, windows: [WindowInfo]) -> [WindowInfo] {
        guard windows.count > 1, Permissions.accessibilityGranted else { return windows }
        let axApp = AXUIElementCreateApplication(pid)
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &val) == .success,
              let axWindows = val as? [AXUIElement] else { return windows }

        var axOrder: [CGWindowID: Int] = [:]
        for (i, axWin) in axWindows.enumerated() {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(axWin, &wid) == .success, wid > 0 {
                if axOrder[wid] == nil {
                    axOrder[wid] = i
                }
            }
        }

        var focusedVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedVal) == .success,
           let focusedElem = focusedVal as! AXUIElement? {
            var focusedWid: CGWindowID = 0
            if _AXUIElementGetWindow(focusedElem, &focusedWid) == .success, focusedWid > 0 {
                axOrder[focusedWid] = -1
            }
        }

        return windows.sorted { (w1, w2) -> Bool in
            let pos1 = axOrder[w1.id] ?? Int.max
            let pos2 = axOrder[w2.id] ?? Int.max
            if pos1 != pos2 {
                return pos1 < pos2
            }
            return false
        }
    }

    /// Background collector for accessory subroles and missing window titles.
    static func fetchBackgroundAXMetadata(allowTitleQueries: Bool) -> (subroles: [pid_t: [CGWindowID: String]], titles: [CGWindowID: String]) {
        guard Permissions.accessibilityGranted else { return ([:], [:]) }
        var subroles: [pid_t: [CGWindowID: String]] = [:]
        var titles: [CGWindowID: String] = [:]
        let myPID = ProcessInfo.processInfo.processIdentifier

        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid != myPID, !app.isTerminated,
                  !WindowQuirksFilter.shouldIgnoreApp(bundleID: app.bundleIdentifier) else { continue }

            if app.activationPolicy == .accessory {
                subroles[pid] = fetchAXWindowSubroles(pid: pid)
            } else if allowTitleQueries && app.activationPolicy == .regular {
                let axApp = AXUIElementCreateApplication(pid)
                var val: CFTypeRef?
                if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &val) == .success,
                   let windows = val as? [AXUIElement] {
                    for w in windows {
                        var wNum: CGWindowID = 0
                        if _AXUIElementGetWindow(w, &wNum) == .success, wNum > 0 {
                            var titleVal: CFTypeRef?
                            if AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &titleVal) == .success,
                               let str = titleVal as? String, !str.isEmpty {
                                titles[wNum] = str
                            }
                        }
                    }
                }
            }
        }
        return (subroles, titles)
    }

    private static func fetchAXWindowSubroles(pid: pid_t) -> [CGWindowID: String] {
        guard Permissions.accessibilityGranted else { return [:] }
        let axApp = AXUIElementCreateApplication(pid)
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &val) == .success,
              let windows = val as? [AXUIElement] else { return [:] }
        var map: [CGWindowID: String] = [:]
        for w in windows {
            var wNum: CGWindowID = 0
            if _AXUIElementGetWindow(w, &wNum) == .success, wNum > 0 {
                var subVal: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &subVal)
                map[wNum] = (subVal as? String) ?? ""
            }
        }
        return map
    }

    private static func fetchAXTitle(pid: pid_t, wid: CGWindowID) -> String? {
        guard Permissions.accessibilityGranted else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &val) == .success,
              let windows = val as? [AXUIElement] else { return nil }
        for w in windows {
            var wNum: CGWindowID = 0
            if _AXUIElementGetWindow(w, &wNum) == .success, wNum == wid {
                var titleVal: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &titleVal) == .success,
                   let str = titleVal as? String, !str.isEmpty {
                    return str
                }
            }
        }
        return nil
    }
}
