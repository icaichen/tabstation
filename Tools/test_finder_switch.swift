import AppKit
import CoreGraphics

func post(_ type: CGEventType, keycode: UInt16, flags: CGEventFlags = []) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keycode, keyDown: type == .keyDown) else { return }
    event.flags = type == .keyDown ? flags : []
    event.post(tap: .cghidEventTap)
}

@main
struct FinderSwitchTest {
    static func main() {
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            finder.activate(options: [.activateIgnoringOtherApps])
        }
        usleep(300_000)

        print("Posting Option + ` (50)...")
        post(.keyDown, keycode: 58, flags: [.maskAlternate])
        usleep(120_000)
        post(.keyDown, keycode: 50, flags: [.maskAlternate])
        Thread.sleep(forTimeInterval: 0.8)

        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for entry in list {
            let name = entry[kCGWindowOwnerName as String] as? String ?? ""
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 0
            let bounds = entry[kCGWindowBounds as String] as? [String: Any] ?? [:]
            if name == "TabStation" && layer == 101 {
                print("TabStation panel: alpha=\(alpha), bounds=\(bounds)")
            }
        }

        print("Tapping ` again to move selection...")
        post(.keyUp, keycode: 50, flags: [.maskAlternate])
        usleep(60_000)
        post(.keyDown, keycode: 50, flags: [.maskAlternate])
        Thread.sleep(forTimeInterval: 0.5)

        print("Releasing Option to commit...")
        post(.keyUp, keycode: 50)
        usleep(60_000)
        post(.keyUp, keycode: 58)
    }
}
