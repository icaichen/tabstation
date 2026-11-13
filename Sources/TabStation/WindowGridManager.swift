import AppKit
import ApplicationServices

/// Manages visual grid snapping, window tiling, and multi-monitor window placement.
enum WindowGridManager {

    enum SnapZone {
        case leftHalf
        case rightHalf
        case topHalf
        case bottomHalf
        case maximize
        case center
        case leftThird
        case leftTwoThirds
        case rightThird
        case rightTwoThirds
        case topLeftQuarter
        case topRightQuarter
        case bottomLeftQuarter
        case bottomRightQuarter

        var displayName: String {
            switch self {
            case .leftHalf: return L10n.t("Left Half (1/2)", "左半屏 (1/2)")
            case .rightHalf: return L10n.t("Right Half (1/2)", "右半屏 (1/2)")
            case .topHalf: return L10n.t("Top Half", "上半屏")
            case .bottomHalf: return L10n.t("Bottom Half", "下半屏")
            case .maximize: return L10n.t("Maximized", "最大化")
            case .center: return L10n.t("Centered (70%)", "居中 (70%)")
            case .leftThird: return L10n.t("Left Third (1/3)", "左侧三分之一 (1/3)")
            case .leftTwoThirds: return L10n.t("Left Two-Thirds (2/3)", "左侧三分之二 (2/3)")
            case .rightThird: return L10n.t("Right Third (1/3)", "右侧三分之一 (1/3)")
            case .rightTwoThirds: return L10n.t("Right Two-Thirds (2/3)", "右侧三分之二 (2/3)")
            case .topLeftQuarter: return L10n.t("Top-Left Quarter", "左上四分之一")
            case .topRightQuarter: return L10n.t("Top-Right Quarter", "右上四分之一")
            case .bottomLeftQuarter: return L10n.t("Bottom-Left Quarter", "左下四分之一")
            case .bottomRightQuarter: return L10n.t("Bottom-Right Quarter", "右下四分之一")
            }
        }
    }

    /// Stores the last applied snap and timestamp to allow consecutive arrow presses to cycle ratios (e.g. 1/2 -> 1/3 -> 2/3).
    private static var lastSnapWindowID: CGWindowID = 0
    private static var lastSnapZone: SnapZone?
    private static var lastSnapTime: TimeInterval = 0
    private static var originalFrames: [CGWindowID: CGRect] = [:]

    // MARK: - Snapping API

    @discardableResult
    static func snap(window: WindowInfo, to zone: SnapZone, targetScreen: NSScreen? = nil) -> String {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return L10n.t("No screens detected", "未检测到显示器") }

        // Save original frame if first time snapping this window
        if originalFrames[window.id] == nil {
            originalFrames[window.id] = window.bounds
        }

        // Determine target screen: either provided or the screen where the window currently resides
        let screen = targetScreen ?? screenContaining(window: window)
        let quartzVis = quartzVisibleFrame(for: screen)
        let targetRect = calculateTargetRect(for: zone, in: quartzVis)

        guard applyRect(targetRect, to: window) else {
            return L10n.t("Accessibility access denied", "缺少辅助功能权限")
        }

        lastSnapWindowID = window.id
        lastSnapZone = zone
        lastSnapTime = ProcessInfo.processInfo.systemUptime

        let screenName = screen.localizedName.isEmpty ? L10n.t("Display", "显示器") : screen.localizedName
        return screens.count > 1
            ? L10n.t("Snapped \(window.ownerName) to \(zone.displayName) on \(screenName)", "已将 \(window.ownerName) 贴靠至 \(screenName) \(zone.displayName)")
            : L10n.t("Snapped \(window.ownerName) to \(zone.displayName)", "已将 \(window.ownerName) 贴靠至\(zone.displayName)")
    }

    /// Cycles left half -> left third -> left two-thirds on consecutive presses.
    @discardableResult
    static func cycleLeft(window: WindowInfo, targetScreen: NSScreen? = nil) -> String {
        let now = ProcessInfo.processInfo.systemUptime
        let isConsecutive = (window.id == lastSnapWindowID) && (now - lastSnapTime < 1.5)

        let nextZone: SnapZone
        if isConsecutive {
            switch lastSnapZone {
            case .leftHalf: nextZone = .leftThird
            case .leftThird: nextZone = .leftTwoThirds
            default: nextZone = .leftHalf
            }
        } else {
            nextZone = .leftHalf
        }
        return snap(window: window, to: nextZone, targetScreen: targetScreen)
    }

    /// Cycles right half -> right two-thirds -> right third on consecutive presses.
    @discardableResult
    static func cycleRight(window: WindowInfo, targetScreen: NSScreen? = nil) -> String {
        let now = ProcessInfo.processInfo.systemUptime
        let isConsecutive = (window.id == lastSnapWindowID) && (now - lastSnapTime < 1.5)

        let nextZone: SnapZone
        if isConsecutive {
            switch lastSnapZone {
            case .rightHalf: nextZone = .rightTwoThirds
            case .rightTwoThirds: nextZone = .rightThird
            default: nextZone = .rightHalf
            }
        } else {
            nextZone = .rightHalf
        }
        return snap(window: window, to: nextZone, targetScreen: targetScreen)
    }

    /// Toggles maximize and top half on consecutive presses.
    @discardableResult
    static func cycleUp(window: WindowInfo, targetScreen: NSScreen? = nil) -> String {
        let now = ProcessInfo.processInfo.systemUptime
        let isConsecutive = (window.id == lastSnapWindowID) && (now - lastSnapTime < 1.5)

        let nextZone: SnapZone = (isConsecutive && lastSnapZone == .maximize) ? .topHalf : .maximize
        return snap(window: window, to: nextZone, targetScreen: targetScreen)
    }

    /// Restores original frame or centers window.
    @discardableResult
    static func cycleDown(window: WindowInfo, targetScreen: NSScreen? = nil) -> String {
        let now = ProcessInfo.processInfo.systemUptime
        let isConsecutive = (window.id == lastSnapWindowID) && (now - lastSnapTime < 1.5)

        if isConsecutive && lastSnapZone == .center {
            return snap(window: window, to: .bottomHalf, targetScreen: targetScreen)
        }

        if let orig = originalFrames[window.id] {
            if applyRect(orig, to: window) {
                lastSnapWindowID = window.id
                lastSnapZone = nil
                lastSnapTime = now
                return L10n.t("Restored Original Frame", "已恢复窗口原始尺寸")
            }
        }
        return snap(window: window, to: .center, targetScreen: targetScreen)
    }

    // MARK: - Geometry Calculation

    static func calculateTargetRect(for zone: SnapZone, in vis: CGRect) -> CGRect {
        let vx = vis.origin.x
        let vy = vis.origin.y
        let vw = vis.width
        let vh = vis.height

        let halfW = (vw / 2).rounded()
        let halfH = (vh / 2).rounded()
        let thirdW = (vw / 3).rounded()
        let twoThirdsW = (vw * 2 / 3).rounded()

        switch zone {
        case .leftHalf:
            return CGRect(x: vx, y: vy, width: halfW, height: vh)
        case .rightHalf:
            return CGRect(x: vx + halfW, y: vy, width: vw - halfW, height: vh)
        case .leftThird:
            return CGRect(x: vx, y: vy, width: thirdW, height: vh)
        case .leftTwoThirds:
            return CGRect(x: vx, y: vy, width: twoThirdsW, height: vh)
        case .rightThird:
            return CGRect(x: vx + twoThirdsW, y: vy, width: vw - twoThirdsW, height: vh)
        case .rightTwoThirds:
            return CGRect(x: vx + (vw - twoThirdsW), y: vy, width: twoThirdsW, height: vh)
        case .topHalf:
            return CGRect(x: vx, y: vy, width: vw, height: halfH)
        case .bottomHalf:
            return CGRect(x: vx, y: vy + halfH, width: vw, height: vh - halfH)
        case .maximize:
            return CGRect(x: vx, y: vy, width: vw, height: vh)
        case .center:
            let cw = (vw * 0.72).rounded()
            let ch = (vh * 0.78).rounded()
            return CGRect(x: vx + ((vw - cw) / 2).rounded(), y: vy + ((vh - ch) / 2).rounded(), width: cw, height: ch)
        case .topLeftQuarter:
            return CGRect(x: vx, y: vy, width: halfW, height: halfH)
        case .topRightQuarter:
            return CGRect(x: vx + halfW, y: vy, width: vw - halfW, height: halfH)
        case .bottomLeftQuarter:
            return CGRect(x: vx, y: vy + halfH, width: halfW, height: vh - halfH)
        case .bottomRightQuarter:
            return CGRect(x: vx + halfW, y: vy + halfH, width: vw - halfW, height: vh - halfH)
        }
    }

    // MARK: - Screen Coordinate Helpers

    static func screenContaining(window: WindowInfo) -> NSScreen {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return screens.first ?? NSScreen() }

        let winCenter = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        for screen in screens {
            let qf = quartzFrame(for: screen)
            if qf.contains(winCenter) {
                return screen
            }
        }

        // Fallback: screen with maximum area intersection
        var bestScreen = screens[0]
        var maxIntersection: CGFloat = -1
        for screen in screens {
            let qf = quartzFrame(for: screen)
            let inter = qf.intersection(window.bounds)
            let area = inter.width * inter.height
            if area > maxIntersection {
                maxIntersection = area
                bestScreen = screen
            }
        }
        return bestScreen
    }

    static func quartzFrame(for screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cf = screen.frame
        return CGRect(
            x: cf.origin.x,
            y: primaryHeight - (cf.origin.y + cf.height),
            width: cf.width,
            height: cf.height
        )
    }

    static func quartzVisibleFrame(for screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let vf = screen.visibleFrame
        return CGRect(
            x: vf.origin.x,
            y: primaryHeight - (vf.origin.y + vf.height),
            width: vf.width,
            height: vf.height
        )
    }

    // MARK: - Apply Frame to AX Window

    static func applyRect(_ rect: CGRect, to window: WindowInfo, bringToFront: Bool = true) -> Bool {
        guard Permissions.accessibilityGranted else { return false }
        guard let axWindow = WindowActivator.findAXWindow(in: window) else { return false }

        // If minimized, unminimize it first
        var minVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minVal) == .success,
           (minVal as? NSNumber)?.boolValue == true {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, BoolValue.false)
        }

        var targetPos = CGPoint(x: rect.origin.x, y: rect.origin.y)
        var targetSize = CGSize(width: rect.width, height: rect.height)

        if let posVal = AXValueCreate(.cgPoint, &targetPos) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &targetSize) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal)
        }
        // Repeat position once to ensure bounds clamping didn't shift origin
        if let posVal = AXValueCreate(.cgPoint, &targetPos) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
        }

        if bringToFront {
            WindowActivator.raiseToFront(window: window, axWindow: axWindow)
        } else {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
        return true
    }
}
