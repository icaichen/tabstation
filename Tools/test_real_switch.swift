import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: inout CGWindowID) -> AXError

@main
struct RealSwitchTest {
    static func main() {
        guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else {
            print("Chrome not running")
            return
        }

        let pid = chrome.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &val) == .success,
              let windows = val as? [AXUIElement] else {
            print("Failed to get windows via AX")
            return
        }

        print("AX Windows count: \(windows.count)")
        for (i, win) in windows.enumerated() {
            var wid: CGWindowID = 0
            _ = _AXUIElementGetWindow(win, &wid)
            var titleVal: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleVal)
            let title = (titleVal as? String) ?? ""
            print("  [\(i)] CGWindowID: \(wid), title: \"\(title)\"")
        }
    }
}
