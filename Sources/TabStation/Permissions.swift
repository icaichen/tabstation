import AppKit
import ApplicationServices
import CoreGraphics

/// TabStation needs two TCC permissions, and both are optional in the sense
/// that the app stays usable without them — it just gets less capable.
///
///  - **Accessibility** — required for the global key event tap (otherwise
///    `⌥Tab` can't be intercepted at all) and for raising a *specific* window
///    rather than just its app.
///  - **Screen Recording** — required to read window titles and to capture
///    real thumbnails. Without it we fall back to large app icons.
enum Permissions {
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt for Accessibility. Safe to call repeatedly —
    /// macOS only prompts once, after that it's a no-op.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Shows the system prompt for Screen Recording. Safe to call repeatedly.
    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openAccessibilitySettings() {
        open("Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        open("Privacy_ScreenCapture")
    }

    private static func open(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Everything granted? Used to decide whether to show the onboarding alert.
    static var allGranted: Bool {
        accessibilityGranted && screenRecordingGranted
    }
}