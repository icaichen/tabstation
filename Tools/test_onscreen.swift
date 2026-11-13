import AppKit
import CoreGraphics

let options: CGWindowListOption = [.optionAll]
guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("Cannot get windows")
    exit(1)
}

for e in list {
    let layer = (e[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
    guard layer == 0 else { continue }
    let owner = e[kCGWindowOwnerName as String] as? String ?? ""
    let pid = (e[kCGWindowOwnerPID as String] as? NSNumber)?.intValue ?? 0
    let id = (e[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
    let onscreen = (e[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
    let bounds = e[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let name = e[kCGWindowName as String] as? String ?? ""

    if ["Google Chrome", "Finder", "Terminal"].contains(owner) {
        print("[\(owner) pid:\(pid)] win:\(id) onscreen=\(String(describing: onscreen)) title=\"\(name)\" bounds=\(bounds)")
    }
}
