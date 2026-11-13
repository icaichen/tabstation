import AppKit

/// Discovers open tabs in running macOS web browsers and provides tab-level activation.
final class BrowserTabService {

    static let shared = BrowserTabService()

    private struct SupportedBrowser {
        let name: String
        let bundleID: String
        let kind: BrowserKind

        enum BrowserKind {
            case chromium
            case safari
            case arc
        }
    }

    private let browsers: [SupportedBrowser] = [
        SupportedBrowser(name: "Google Chrome", bundleID: "com.google.Chrome", kind: .chromium),
        SupportedBrowser(name: "Safari", bundleID: "com.apple.Safari", kind: .safari),
        SupportedBrowser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", kind: .chromium),
        SupportedBrowser(name: "Brave Browser", bundleID: "com.brave.Browser", kind: .chromium),
        SupportedBrowser(name: "Arc", bundleID: "company.thebrowser.Arc", kind: .arc)
    ]

    /// Fetches all open tabs across all running supported browsers.
    func fetchTabs() -> [WindowInfo] {
        var result: [WindowInfo] = []
        let runningApps = NSWorkspace.shared.runningApplications

        for browser in browsers {
            guard let app = runningApps.first(where: {
                $0.bundleIdentifier == browser.bundleID || $0.localizedName == browser.name
            }) else {
                continue
            }

            let tabs = queryTabs(for: browser, pid: app.processIdentifier)
            result.append(contentsOf: tabs)
        }

        return result
    }

    private func queryTabs(for browser: SupportedBrowser, pid: pid_t) -> [WindowInfo] {
        let scriptSource: String
        switch browser.kind {
        case .chromium, .arc:
            scriptSource = """
            tell application "\(browser.name)"
                set output to ""
                set wIdx to 0
                repeat with w in windows
                    set wIdx to wIdx + 1
                    set tIdx to 0
                    repeat with t in tabs of w
                        set tIdx to tIdx + 1
                        set output to output & (wIdx as string) & ":::" & (tIdx as string) & ":::" & (title of t) & ":::" & (URL of t) & "---"
                    end repeat
                end repeat
                return output
            end tell
            """
        case .safari:
            scriptSource = """
            tell application "Safari"
                set output to ""
                set wIdx to 0
                repeat with w in windows
                    set wIdx to wIdx + 1
                    set tIdx to 0
                    repeat with t in tabs of w
                        set tIdx to tIdx + 1
                        set output to output & (wIdx as string) & ":::" & (tIdx as string) & ":::" & (name of t) & ":::" & (URL of t) & "---"
                    end repeat
                end repeat
                return output
            end tell
            """
        }

        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else { return [] }
        let descriptor = script.executeAndReturnError(&error)
        guard let output = descriptor.stringValue, !output.isEmpty else { return [] }

        var items: [WindowInfo] = []
        let entries = output.components(separatedBy: "---")

        for entry in entries where !entry.isEmpty {
            let parts = entry.components(separatedBy: ":::")
            guard parts.count >= 4,
                  let wIdx = Int(parts[0]),
                  let tIdx = Int(parts[1]) else { continue }

            let title = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let url = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty || !url.isEmpty else { continue }

            let virtualID = CGWindowID(
                0x7F000000
                | ((UInt32(pid) & 0x7F) << 16)
                | ((UInt32(wIdx) & 0xFF) << 8)
                | (UInt32(tIdx) & 0xFF)
            )

            let tabInfo = BrowserTabInfo(
                url: url,
                winIndex: wIdx,
                tabIndex: tIdx,
                browserName: browser.name
            )

            let info = WindowInfo(
                id: virtualID,
                pid: pid,
                ownerName: browser.name,
                bundleID: browser.bundleID,
                title: title.isEmpty ? url : title,
                bounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
                isMinimized: false,
                browserTab: tabInfo
            )
            items.append(info)
        }

        return items
    }

    /// Activates a specific browser tab via AppleScript.
    @discardableResult
    static func activate(tab: BrowserTabInfo) -> Bool {
        let scriptSource: String
        switch tab.browserName {
        case "Safari":
            scriptSource = """
            tell application "Safari"
                activate
                set index of window \(tab.winIndex) to 1
                set current tab of window 1 to tab \(tab.tabIndex) of window 1
            end tell
            """
        case "Arc":
            scriptSource = """
            tell application "Arc"
                activate
                tell window \(tab.winIndex)
                    tell tab \(tab.tabIndex)
                        select
                    end tell
                end tell
            end tell
            """
        default: // Chromium browsers: Chrome, Edge, Brave
            scriptSource = """
            tell application "\(tab.browserName)"
                activate
                set index of window \(tab.winIndex) to 1
                set active tab index of window 1 to \(tab.tabIndex)
            end tell
            """
        }

        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else { return false }
        script.executeAndReturnError(&error)
        return error == nil
    }

    /// Queries the currently active URL of the frontmost tab for a given browser process.
    static func queryActiveURL(for pid: pid_t) -> String? {
        let runningApps = NSWorkspace.shared.runningApplications
        guard let app = runningApps.first(where: { $0.processIdentifier == pid }) else { return nil }
        let bundleID = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? ""

        let scriptSource: String
        if bundleID.contains("Chrome") || appName.contains("Chrome") || bundleID.contains("Brave") || bundleID.contains("Edge") || bundleID.contains("Arc") {
            scriptSource = """
            tell application "\(appName)"
                if (count of windows) > 0 then
                    return URL of active tab of front window
                end if
            end tell
            """
        } else if bundleID.contains("Safari") || appName.contains("Safari") {
            scriptSource = """
            tell application "Safari"
                if (count of windows) > 0 then
                    return URL of current tab of front window
                end if
            end tell
            """
        } else {
            return nil
        }

        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        let descriptor = script.executeAndReturnError(&error)
        return descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
