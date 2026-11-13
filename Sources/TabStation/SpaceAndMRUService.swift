import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - SkyLight Spaces SPI

/// Safe, lazy-loaded wrapper around SkyLight private functions for macOS Spaces awareness.
/// Allows TabStation to discover windows across all virtual desktops and Full-Screen Spaces
/// while filtering out off-screen ghost helper windows that do not belong to any Space.
enum SkyLightSpaces {

    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias GetActiveSpaceFn = @convention(c) (Int32) -> UInt64
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY
    )

    private static let mainConnectionID: MainConnectionIDFn? = {
        guard let handle else { return nil }
        let sym = dlsym(handle, "SLSMainConnectionID") ?? dlsym(handle, "CGSMainConnectionID")
        return sym.map { unsafeBitCast($0, to: MainConnectionIDFn.self) }
    }()

    private static let getActiveSpace: GetActiveSpaceFn? = {
        guard let handle else { return nil }
        let sym = dlsym(handle, "SLSGetActiveSpace") ?? dlsym(handle, "CGSGetActiveSpace")
        return sym.map { unsafeBitCast($0, to: GetActiveSpaceFn.self) }
    }()

    private static let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn? = {
        guard let handle else { return nil }
        let sym = dlsym(handle, "SLSCopyManagedDisplaySpaces") ?? dlsym(handle, "CGSCopyManagedDisplaySpaces")
        return sym.map { unsafeBitCast($0, to: CopyManagedDisplaySpacesFn.self) }
    }()

    private static let copySpacesForWindows: CopySpacesForWindowsFn? = {
        guard let handle else { return nil }
        let sym = dlsym(handle, "SLSCopySpacesForWindows") ?? dlsym(handle, "CGSCopySpacesForWindows")
        return sym.map { unsafeBitCast($0, to: CopySpacesForWindowsFn.self) }
    }()

    /// Selector mask 0x7 includes user spaces, fullscreen spaces, and system spaces.
    private static let allSpacesMask: Int32 = 0x7

    static var isAvailable: Bool {
        mainConnectionID != nil && copySpacesForWindows != nil
    }

    static func activeSpaceID() -> UInt64? {
        guard let conn = mainConnectionID?(), let getActive = getActiveSpace else { return nil }
        let space = getActive(conn)
        return space > 0 ? space : nil
    }

    /// Returns the currently visible Space ID for every connected display.
    /// On multi-monitor setups ("Displays have separate Spaces"), `SLSGetActiveSpace`
    /// only returns one display's active Space, missing windows visible on other monitors.
    static func activeSpaceIDs() -> Set<UInt64> {
        guard let conn = mainConnectionID?() else { return [] }
        var ids = Set<UInt64>()
        if let copyDisplays = copyManagedDisplaySpaces,
           let rawDisplays = copyDisplays(conn)?.takeRetainedValue() as? [[String: Any]] {
            for display in rawDisplays {
                if let current = display["Current Space"] as? [String: Any],
                   let spaceID = (current["ManagedSpaceID"] as? NSNumber)?.uint64Value,
                   spaceID > 0 {
                    ids.insert(spaceID)
                }
            }
        }
        if ids.isEmpty, let primary = activeSpaceID() {
            ids.insert(primary)
        }
        return ids
    }

    /// Returns the list of Space IDs containing `windowID`.
    /// An empty array means the window is an unmapped helper/ghost surface not present in any Space.
    static func spaces(for windowID: CGWindowID) -> [UInt64]? {
        guard let conn = mainConnectionID?(), let copySpaces = copySpacesForWindows else {
            return nil
        }
        let arr = [NSNumber(value: windowID)] as CFArray
        guard let unmanaged = copySpaces(conn, allSpacesMask, arr) else {
            return []
        }
        let result = unmanaged.takeRetainedValue() as? [NSNumber] ?? []
        return result.map { $0.uint64Value }
    }
}

// MARK: - Zero-Polling MRU Focus Tracker

/// Tracks exact Most Recently Used (MRU) window order with ZERO background polling.
/// Updated only when TabStation switches windows or when NSWorkspace notifies of an app switch.
final class MRUTracker: @unchecked Sendable {

    static let shared = MRUTracker()

    private let lock = NSLock()
    private var sequence: UInt64 = 0
    private var windowRanks: [CGWindowID: UInt64] = [:]

    private init() {}

    func recordFocus(windowID: CGWindowID) {
        guard windowID > 0 else { return }
        lock.lock()
        sequence += 1
        windowRanks[windowID] = sequence
        lock.unlock()
    }

    /// Queries only the newly activated frontmost app (1 lightweight AX call) when macOS switches apps.
    func recordFrontmostAppWindow(pid: pid_t) {
        guard pid > 0, Permissions.accessibilityGranted else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let axApp = AXUIElementCreateApplication(pid)
            var focusedVal: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedVal) == .success,
                  let focusedElem = focusedVal else { return }
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(focusedElem as! AXUIElement, &wid) == .success, wid > 0 {
                self?.recordFocus(windowID: wid)
            }
        }
    }

    func rank(for windowID: CGWindowID) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return windowRanks[windowID] ?? 0
    }
}

// MARK: - App Quirks & Ghost Window Filter

/// Filters out system non-window overlays and known weird helper windows from Electron, Java/JetBrains, Finder, etc.
enum WindowQuirksFilter {

    private static let systemIgnoredBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.WindowManager",
        "com.apple.screencaptureui",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.UserNotificationCenter",
        "com.apple.universalcontrol",
        "com.apple.coreservices.uiagent",
        "com.apple.MenuBarAgent",
        "com.apple.campo",
        "com.apple.TextInputUI.xpc.CursorUIViewService",
        "com.apple.appkit.xpc.openAndSavePanelService",
        "com.apple.SafariPlatformSupport.Helper"
    ]

    static var userExcludedBundleIDs: Set<String> {
        get {
            let arr = UserDefaults.standard.stringArray(forKey: "TabStation.excludedBundleIDs") ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: "TabStation.excludedBundleIDs")
        }
    }

    static func shouldIgnoreApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return systemIgnoredBundleIDs.contains(bundleID) || userExcludedBundleIDs.contains(bundleID)
    }

    /// Returns true if a window entry is a known ghost/auxiliary surface rather than a real user window.
    static func isGhostWindow(
        bundleID: String?,
        ownerName: String,
        title: String,
        bounds: CGRect,
        isOnScreen: Bool,
        onActiveSpace: Bool,
        isAppHidden: Bool,
        spaces: [UInt64]?
    ) -> Bool {
        // 1. If SkyLight Spaces is available and the window does not belong to ANY Space,
        // it is an off-screen helper/ghost surface (common in Electron, Office, Adobe, Chromium).
        if let spaces, spaces.isEmpty {
            return true
        }

        // 2. If the window belongs to an active Space on any display yet is NOT on-screen
        // while its owning app is NOT hidden, the app has ordered it out / closed it
        // (e.g. WeChat closed/popup surfaces, CocosCreator/Electron background panels).
        // Real minimized windows are collected separately via AX `kAXMinimizedAttribute`.
        if !isOnScreen && onActiveSpace && !isAppHidden {
            return true
        }

        // 3. Off-screen windows on other Spaces with empty titles are almost always hidden helper surfaces.
        if !isOnScreen && !isAppHidden && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        // 4. Finder creates an invisible full-screen desktop window at layer 0 with an empty title.
        if bundleID == "com.apple.finder" && title.isEmpty {
            for screen in NSScreen.screens {
                if abs(bounds.width - screen.frame.width) < 2 && abs(bounds.height - screen.frame.height) < 2 {
                    return true
                }
            }
        }

        // 5. JetBrains / Java / Steam / Electron tooltips or invisible popups with empty titles
        // and suspiciously small dimensions.
        if title.isEmpty && (bounds.width < 150 || bounds.height < 120) {
            return true
        }

        // 6. Known specific ghost titles
        if ownerName == "Steam" && title == "Steam" && bounds.width < 300 {
            return true
        }

        return false
    }
}
