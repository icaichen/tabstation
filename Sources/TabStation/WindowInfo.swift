import AppKit
import CoreGraphics

/// Information about a browser tab when represented as a window item.
struct BrowserTabInfo: Hashable {
    let url: String
    let winIndex: Int
    let tabIndex: Int
    let browserName: String

    var domain: String {
        guard let u = URL(string: url), let host = u.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A single switchable window or browser tab, as reported by the system.
struct WindowInfo: Hashable {
    /// `kCGWindowNumber` — also equals the AX `AXWindowNumber`, which is how we
    /// find the matching AXUIElement when we need to raise this exact window.
    let id: CGWindowID
    let pid: pid_t
    let ownerName: String
    let bundleID: String?
    /// Empty when Screen Recording is denied: macOS redacts window names from
    /// the window list unless the app is trusted.
    let title: String
    /// Screen coordinates, top-left origin (CoreGraphics convention).
    let bounds: CGRect
    var isMinimized: Bool = false
    var isOnActiveSpace: Bool = true
    var browserTab: BrowserTabInfo? = nil

    var appName: String { ownerName }

    /// Width / height clamped to sane values so a degenerate window can't blow
    /// up thumbnail sizing.
    var aspectRatio: CGFloat {
        guard bounds.height > 0 else { return 1.6 }
        return max(0.35, min(3.2, bounds.width / bounds.height))
    }

    /// What we show under the thumbnail. Prefers the real window title and
    /// degrades to "App — Window 3" style labels when titles are unavailable.
    func caption(windowNumber: Int, windowCount: Int) -> String {
        if let tab = browserTab {
            let d = tab.domain
            return d.isEmpty ? title : "\(title) · \(d)"
        }
        let base: String
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = title
        } else {
            base = ownerName
        }
        return isMinimized ? L10n.t("\(base) (Minimized)", "\(base)（已最小化）") : base
    }
}
