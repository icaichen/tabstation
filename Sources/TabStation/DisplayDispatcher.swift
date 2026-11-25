import AppKit
import ApplicationServices

/// Handles moving windows across multiple physical or virtual displays.
enum DisplayDispatcher {

    private static func liveBounds(for axWindow: AXUIElement, fallback: CGRect) -> CGRect {
        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        var pos = fallback.origin
        var size = fallback.size

        if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posVal) == .success,
           let posVal, CFGetTypeID(posVal) == AXValueGetTypeID() {
            AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
        }
        if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeVal) == .success,
           let sizeVal, CFGetTypeID(sizeVal) == AXValueGetTypeID() {
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        }

        guard size.width >= 50, size.height >= 50 else { return fallback }
        return CGRect(origin: pos, size: size)
    }

    /// Moves the specified window to the next screen in rotation.
    /// Returns a human-readable status message for user feedback.
    @discardableResult
    static func moveToNextDisplay(window: WindowInfo) -> String {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            return L10n.t("Single display detected", "仅检测到单个显示器")
        }

        guard let axWindow = WindowActivator.findAXWindow(in: window) else {
            return L10n.t("Cannot access window via Accessibility", "无法通过辅助功能访问该窗口")
        }

        // Always read live bounds from AX so repeated presses of `D` cycle through displays
        // instead of reusing the stale snapshot bounds from when the switcher opened.
        let currentBounds = liveBounds(for: axWindow, fallback: window.bounds)

        // Primary screen height is needed to convert Cocoa (bottom-left) to Quartz (top-left)
        let primaryHeight = screens.first?.frame.height ?? 0

        // Window center in Quartz coordinates
        let winCenter = CGPoint(x: currentBounds.midX, y: currentBounds.midY)

        // Convert all screen bounds to Quartz coordinates
        let screenQuartzFrames = screens.map { s -> CGRect in
            let cf = s.frame
            return CGRect(
                x: cf.origin.x,
                y: primaryHeight - (cf.origin.y + cf.height),
                width: cf.width,
                height: cf.height
            )
        }

        let screenQuartzVisibleFrames = screens.map { s -> CGRect in
            let vf = s.visibleFrame
            return CGRect(
                x: vf.origin.x,
                y: primaryHeight - (vf.origin.y + vf.height),
                width: vf.width,
                height: vf.height
            )
        }

        // Identify which screen the window is currently mostly on
        var currentScreenIndex = 0
        for (i, qf) in screenQuartzFrames.enumerated() {
            if qf.contains(winCenter) {
                currentScreenIndex = i
                break
            }
        }

        let targetScreenIndex = (currentScreenIndex + 1) % screens.count
        let currentVis = screenQuartzVisibleFrames[currentScreenIndex]
        let targetVis = screenQuartzVisibleFrames[targetScreenIndex]

        let isMaximized = (currentBounds.width >= currentVis.width - 30) && (currentBounds.height >= currentVis.height - 30)

        let newW: CGFloat
        let newH: CGFloat
        let newX: CGFloat
        let newY: CGFloat

        if isMaximized {
            newW = targetVis.width
            newH = targetVis.height
            newX = targetVis.origin.x
            newY = targetVis.origin.y
        } else {
            let relX = max(0, min(1, (currentBounds.origin.x - currentVis.origin.x) / max(1, currentVis.width)))
            let relY = max(0, min(1, (currentBounds.origin.y - currentVis.origin.y) / max(1, currentVis.height)))

            // Preserve original window dimensions unless the target display is smaller
            newW = max(320, min(targetVis.width, currentBounds.width)).rounded()
            newH = max(240, min(targetVis.height, currentBounds.height)).rounded()

            let calcX = targetVis.origin.x + (targetVis.width - newW) * relX
            let calcY = targetVis.origin.y + (targetVis.height - newH) * relY

            newX = max(targetVis.origin.x, min(targetVis.origin.x + targetVis.width - newW, calcX)).rounded()
            newY = max(targetVis.origin.y, min(targetVis.origin.y + targetVis.height - newH, calcY)).rounded()
        }

        var targetPos = CGPoint(x: newX, y: newY)
        var targetSize = CGSize(width: newW, height: newH)

        if let posVal = AXValueCreate(.cgPoint, &targetPos) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &targetSize) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal)
        }
        if let posVal = AXValueCreate(.cgPoint, &targetPos) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
        }

        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)

        let targetScreen = screens[targetScreenIndex]
        let displayName = targetScreen.localizedName.isEmpty
            ? L10n.t("Display \(targetScreenIndex + 1)", "显示器 \(targetScreenIndex + 1)")
            : targetScreen.localizedName
        return L10n.t(
            "Moved to \(displayName) (\(Int(targetVis.width))×\(Int(targetVis.height)))",
            "已移至 \(displayName) (\(Int(targetVis.width))×\(Int(targetVis.height)))"
        )
    }

    /// Moves the specified window onto the target screen.
    /// Preserves proportional scale/position or clamps to visible frame.
    @discardableResult
    static func move(window: WindowInfo, to targetScreen: NSScreen) -> Bool {
        let currentScreen = WindowGridManager.screenContaining(window: window)
        guard currentScreen != targetScreen else { return true }

        let currentVis = WindowGridManager.quartzVisibleFrame(for: currentScreen)
        let targetVis = WindowGridManager.quartzVisibleFrame(for: targetScreen)

        guard let axWindow = WindowActivator.findAXWindow(in: window) else {
            return false
        }

        // Unminimize if minimized
        var minVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minVal) == .success,
           (minVal as? NSNumber)?.boolValue == true {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, BoolValue.false)
        }

        // Check if window was effectively maximized on current screen
        let isMaximized = (window.bounds.width >= currentVis.width - 30) && (window.bounds.height >= currentVis.height - 30)

        let newW: CGFloat
        let newH: CGFloat
        let newX: CGFloat
        let newY: CGFloat

        if isMaximized {
            newW = targetVis.width
            newH = targetVis.height
            newX = targetVis.origin.x
            newY = targetVis.origin.y
        } else {
            // Relative offset in current display
            let relX = max(0, min(1, (window.bounds.origin.x - currentVis.origin.x) / max(1, currentVis.width)))
            let relY = max(0, min(1, (window.bounds.origin.y - currentVis.origin.y) / max(1, currentVis.height)))

            newW = min(window.bounds.width, targetVis.width)
            newH = min(window.bounds.height, targetVis.height)

            let calcX = targetVis.origin.x + (targetVis.width - newW) * relX
            let calcY = targetVis.origin.y + (targetVis.height - newH) * relY

            newX = max(targetVis.origin.x, min(targetVis.origin.x + targetVis.width - newW, calcX)).rounded()
            newY = max(targetVis.origin.y, min(targetVis.origin.y + targetVis.height - newH, calcY)).rounded()
        }

        var targetPos = CGPoint(x: newX, y: newY)
        var targetSize = CGSize(width: newW, height: newH)

        if let posVal = AXValueCreate(.cgPoint, &targetPos) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &targetSize) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal)
        }
        if let posVal = AXValueCreate(.cgPoint, &targetPos) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
        }

        WindowActivator.raiseToFront(window: window, axWindow: axWindow)
        return true
    }
}
