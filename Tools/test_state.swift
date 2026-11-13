import AppKit

let front = NSWorkspace.shared.frontmostApplication
print("Frontmost App: \(front?.localizedName ?? "") (pid: \(front?.processIdentifier ?? 0), bundle: \(front?.bundleIdentifier ?? ""))")

let snapshot = WindowEnumerator.snapshot()
print("Windows in snapshot: \(snapshot.windows.count)")
for w in snapshot.windows {
    print("  Window [\(w.id)] app=\(w.ownerName) (pid: \(w.pid)) title=\"\(w.title)\"")
}
