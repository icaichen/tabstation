import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: inout CGWindowID) -> AXError

@main
struct AllAppsTest {
    static func main() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var val: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &val) == .success,
               let windows = val as? [AXUIElement] {
                print("\(app.localizedName ?? "") (pid: \(app.processIdentifier)): \(windows.count) AX windows")
                for w in windows {
                    var titleVal: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &titleVal)
                    print("    - \"\(titleVal as? String ?? "")\"")
                }
            } else {
                print("\(app.localizedName ?? ""): no AX windows")
            }
        }
    }
}
