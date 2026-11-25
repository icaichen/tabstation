import AppKit
import ApplicationServices

/// Private C SPI from HIServices / ApplicationServices that maps an AXUIElement
/// directly to its CGWindowID. This works reliably across all applications
/// (AppKit, Cocoa, Chromium, Electron, etc.), unlike the deprecated AXWindowNumber.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: inout CGWindowID) -> AXError

@_silgen_name("GetProcessForPID")
func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

typealias SLPSSetFrontProcessWithOptionsFunction = @convention(c) (
    UnsafeMutablePointer<ProcessSerialNumber>,
    CGWindowID,
    UInt32
) -> Int32

typealias SLPSPostEventRecordToFunction = @convention(c) (
    UnsafeMutablePointer<ProcessSerialNumber>,
    UnsafeMutablePointer<UInt8>
) -> Int32

private let skyLightHandle: UnsafeMutableRawPointer? = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

private let slpsSetFrontProcessWithOptions: SLPSSetFrontProcessWithOptionsFunction? = {
    guard let handle = skyLightHandle,
          let sym = dlsym(handle, "_SLPSSetFrontProcessWithOptions") else { return nil }
    return unsafeBitCast(sym, to: SLPSSetFrontProcessWithOptionsFunction.self)
}()

private let slpsPostEventRecordTo: SLPSPostEventRecordToFunction? = {
    guard let handle = skyLightHandle,
          let sym = dlsym(handle, "SLPSPostEventRecordTo") else { return nil }
    return unsafeBitCast(sym, to: SLPSPostEventRecordToFunction.self)
}()

private enum MakeKeyWindowEvent {
    static let bufferSize = 0x100
    static let lengthOffset = 0x04
    static let recordLength: UInt8 = 0xf8
    static let eventTypeOffset = 0x08
    static let leftMouseDown: UInt8 = 0x01
    static let leftMouseUp: UInt8 = 0x02
    static let windowLocationOffset = 0x20
    static let offContentPoint = CGPoint(x: 300_000, y: 300_000)
    static let windowIdOffset = 0x3c
    static let unknownFlagOffset = 0x3a
    static let unknownFlagValue: UInt8 = 0x10
}

/// Makes the window key via synthetic down+up event records posted to SkyLight WindowServer.
/// Uses an off-content finite point (never 0xff/NaN bytes) so macOS 27.2 WindowServer never rejects the switch.
private func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID) {
    var wid = wid
    var point = MakeKeyWindowEvent.offContentPoint
    var bytes = [UInt8](repeating: 0, count: MakeKeyWindowEvent.bufferSize)
    bytes[MakeKeyWindowEvent.lengthOffset] = MakeKeyWindowEvent.recordLength
    bytes[MakeKeyWindowEvent.unknownFlagOffset] = MakeKeyWindowEvent.unknownFlagValue
    memcpy(&bytes[MakeKeyWindowEvent.windowIdOffset], &wid, MemoryLayout<CGWindowID>.size)
    memcpy(&bytes[MakeKeyWindowEvent.windowLocationOffset], &point, MemoryLayout<CGPoint>.size)
    bytes[MakeKeyWindowEvent.eventTypeOffset] = MakeKeyWindowEvent.leftMouseDown
    _ = slpsPostEventRecordTo?(&psn, &bytes)
    bytes[MakeKeyWindowEvent.eventTypeOffset] = MakeKeyWindowEvent.leftMouseUp
    _ = slpsPostEventRecordTo?(&psn, &bytes)
}

/// `AXUIElementSetAttributeValue` wants a `CFTypeRef`, not a Swift `Bool`.
enum BoolValue {
    static let `true`: CFTypeRef = unsafeBitCast(kCFBooleanTrue!, to: CFTypeRef.self)
    static let `false`: CFTypeRef = unsafeBitCast(kCFBooleanFalse!, to: CFTypeRef.self)
}

/// Brings a *specific* window forward, not just its application.
///
/// `NSRunningApplication.activate()` alone is governed by macOS 14+ Cooperative
/// Activation and can be silently ignored when called from an inactive `LSUIElement`,
/// or fail on hidden, minimized, `.accessory`, or closed-to-tray apps. This activator
/// sequences unhiding/unminimizing, cooperative + LaunchServices activation, SkyLight
/// front-process + key-window events, and Accessibility focus reliably across all apps.
enum WindowActivator {

    /// Activates an application using modern macOS 14+ Cooperative Activation,
    /// without relying on the deprecated no-op `.activateIgnoringOtherApps` flag.
    private static func activateApplication(_ app: NSRunningApplication) {
        if app.isHidden {
            app.unhide()
        }
        if NSApp.isActive {
            NSApp.yieldActivation(to: app)
        }
        _ = app.activate()
    }

    /// Launches/reopens/activates an application via LaunchServices (`NSWorkspace.openApplication`),
    /// which carries system authority to activate foreground/accessory apps and reopen closed-to-tray windows.
    private static func activateViaLaunchServices(_ app: NSRunningApplication, completion: (() -> Void)? = nil) {
        guard let bundleURL = app.bundleURL else {
            completion?()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            if let completion {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    /// Raises and focuses the exact target window using SkyLight + Accessibility without relaunching.
    private static func focusSpecificWindow(window: WindowInfo, axWindow: AXUIElement? = nil) {
        guard window.id > 0 else { return }

        let targetAX = axWindow ?? (Permissions.accessibilityGranted ? findAXWindow(in: window) : nil)
        if let targetAX {
            var minVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(targetAX, kAXMinimizedAttribute as CFString, &minVal) == .success,
               (minVal as? NSNumber)?.boolValue == true {
                AXUIElementSetAttributeValue(targetAX, kAXMinimizedAttribute as CFString, BoolValue.false)
            }
        }

        var psn = ProcessSerialNumber()
        if GetProcessForPID(window.pid, &psn) == noErr {
            // 0x200 = userGenerated mode: marks the front-switch as user-initiated
            _ = slpsSetFrontProcessWithOptions?(&psn, window.id, 0x200)
            makeKeyWindow(&psn, window.id)
        }

        if let targetAX {
            AXUIElementPerformAction(targetAX, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(targetAX, kAXMainAttribute as CFString, BoolValue.true)
            AXUIElementSetAttributeValue(targetAX, kAXFocusedAttribute as CFString, BoolValue.true)

            let axApp = AXUIElementCreateApplication(window.pid)
            AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, targetAX)
            AXUIElementSetAttributeValue(axApp, kAXMainWindowAttribute as CFString, targetAX)
        }
    }

    static func activate(_ window: WindowInfo) {
        MRUTracker.shared.recordFocus(windowID: window.id, pid: window.pid)
        guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else { return }

        if let tab = window.browserTab {
            // Execute AppleScript tab switch off the main thread so the UI/RunLoop never stalls.
            DispatchQueue.global(qos: .userInteractive).async {
                BrowserTabService.activate(tab: tab)
            }
        }

        // Windowless / closed-to-tray Dock apps (id == 0) need a LaunchServices reopen event
        // (`applicationShouldHandleReopen`) to materialize their main window.
        guard window.id > 0 else {
            activateApplication(app)
            activateViaLaunchServices(app)
            return
        }

        let wasHidden = app.isHidden
        let wasMinimized = window.isMinimized

        // 1. Fast synchronous WindowServer activation (< 0.5ms) with zero blocking AX IPC.
        if wasHidden {
            app.unhide()
        }
        activateApplication(app)
        var psn = ProcessSerialNumber()
        if GetProcessForPID(window.pid, &psn) == noErr {
            _ = slpsSetFrontProcessWithOptions?(&psn, window.id, 0x200)
            makeKeyWindow(&psn, window.id)
        }

        // 2. Single-pass AX unminimize + raise + focus off the main UI thread (never double-queries AX).
        DispatchQueue.global(qos: .userInteractive).async {
            guard Permissions.accessibilityGranted, let axWin = findAXWindow(in: window) else { return }
            var actuallyMinimized = wasMinimized
            var minVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWin, kAXMinimizedAttribute as CFString, &minVal) == .success,
               (minVal as? NSNumber)?.boolValue == true {
                actuallyMinimized = true
                AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, BoolValue.false)
            }
            focusSpecificWindow(window: window, axWindow: axWin)

            if wasHidden || actuallyMinimized {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    guard !app.isTerminated else { return }
                    if !app.isActive {
                        activateApplication(app)
                        activateViaLaunchServices(app) {
                            focusSpecificWindow(window: window, axWindow: axWin)
                        }
                    } else {
                        focusSpecificWindow(window: window, axWindow: axWin)
                    }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    guard !app.isTerminated else { return }
                    if !app.isActive {
                        activateApplication(app)
                        activateViaLaunchServices(app) {
                            focusSpecificWindow(window: window, axWindow: axWin)
                        }
                    }
                }
            }
        }
    }

    /// Brings a specific window forward visually above background apps without stealing key focus from TabStation HUD.
    static func raiseToFront(window: WindowInfo, axWindow: AXUIElement? = nil) {
        if let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated {
            activateApplication(app)
        }
        focusSpecificWindow(window: window, axWindow: axWindow)
    }

    /// Closes a window via Accessibility API by pressing its close button.
    @discardableResult
    static func close(_ window: WindowInfo) -> Bool {
        guard Permissions.accessibilityGranted else { return false }
        guard let axWindow = findAXWindow(in: window) else { return false }

        var closeButton: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButton) == .success,
           let btn = closeButton {
            let result = AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString)
            return result == .success
        }
        return false
    }

    /// Minimizes a window via Accessibility API.
    @discardableResult
    static func minimize(_ window: WindowInfo) -> Bool {
        guard Permissions.accessibilityGranted else { return false }
        guard let axWindow = findAXWindow(in: window) else { return false }

        var minButton: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXMinimizeButtonAttribute as CFString, &minButton) == .success,
           let btn = minButton {
            let result = AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString)
            return result == .success
        }
        // Fallback: directly set minimized attribute
        let result = AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, BoolValue.true)
        return result == .success
    }

    /// Quits the application that owns the window.
    static func quitApp(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    /// Matches the CoreGraphics window ID against the AX window list using _AXUIElementGetWindow.
    static func findAXWindow(in window: WindowInfo) -> AXUIElement? {
        guard window.id > 0 else { return nil }
        let app = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
           let windows = value as? [AXUIElement] {
            for axWindow in windows {
                var wid: CGWindowID = 0
                if _AXUIElementGetWindow(axWindow, &wid) == .success, wid > 0, wid == window.id {
                    return axWindow
                }
            }
        }

        // Fallback: search in children for non-standard window hierarchies
        var childrenVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &childrenVal) == .success,
           let children = childrenVal as? [AXUIElement] {
            for child in children {
                var wid: CGWindowID = 0
                if _AXUIElementGetWindow(child, &wid) == .success, wid > 0, wid == window.id {
                    return child
                }
            }
        }

        return nil
    }
}