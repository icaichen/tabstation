import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

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

    /// Shows the system prompt for Accessibility and nudges AX subsystem
    /// so macOS registers AltDeck in Privacy & Security → Accessibility.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !trusted {
            var focused: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(
                AXUIElementCreateSystemWide(),
                kAXFocusedApplicationAttribute as CFString,
                &focused
            )
        }
    }

    /// Triggers Screen Recording registration via CoreGraphics AND ScreenCaptureKit.
    /// On macOS 15+, ScreenCaptureKit reliably registers the app in
    /// Privacy & Security → Screen & System Audio Recording when promptable.
    static func requestScreenRecording() {
        let granted = CGRequestScreenCaptureAccess()
        if !granted {
            Task.detached(priority: .userInitiated) {
                _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            }
        }
    }

    enum AutomationStatus: Equatable {
        case granted
        case promptable
        case denied
        case unavailable
    }

    /// Queries (and optionally prompts) macOS Automation TCC permission for a target app bundle ID.
    /// Must only pass `askUserIfNeeded: true` from a background queue during an explicit user action.
    static func automationPermission(forBundleID bundleID: String, askUserIfNeeded: Bool = false) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let aeDesc = target.aeDesc else { return OSStatus(procNotFound) }
        return AEDeterminePermissionToAutomateTarget(aeDesc, typeWildCard, typeWildCard, askUserIfNeeded)
    }

    /// Summarizes Automation permission across whichever target apps are currently running.
    static func automationStatus(forBundleIDs bundleIDs: [String]) -> AutomationStatus {
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let activeTargets = bundleIDs.filter { runningIDs.contains($0) }
        guard !activeTargets.isEmpty else { return .unavailable }

        var sawPromptable = false
        var sawGranted = false
        for bundleID in activeTargets {
            let status = automationPermission(forBundleID: bundleID, askUserIfNeeded: false)
            if status == noErr {
                sawGranted = true
            } else if status == OSStatus(errAEEventNotPermitted) {
                return .denied
            } else if status == OSStatus(errAEEventWouldRequireUserConsent) {
                sawPromptable = true
            }
        }
        if sawPromptable { return .promptable }
        if sawGranted { return .granted }
        return .unavailable
    }

    static func openAccessibilitySettings() {
        open("Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        open("Privacy_ScreenCapture")
    }

    static func openAutomationSettings() {
        open("Privacy_Automation")
    }

    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
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