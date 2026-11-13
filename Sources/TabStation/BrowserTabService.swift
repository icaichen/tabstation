import AppKit
import ApplicationServices

/// Discovers open tabs in running macOS web browsers and provides tab-level activation.
final class BrowserTabService {

    static let shared = BrowserTabService()

    struct FetchResult {
        let tabs: [WindowInfo]
        let deniedBrowsers: [String]
    }

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

    private let scriptQueue = DispatchQueue(label: "com.tabstation.BrowserTabService.script", qos: .userInteractive)
    private var compiledTabScripts: [String: NSAppleScript] = [:]

    var supportedBundleIDs: [String] {
        browsers.map(\.bundleID)
    }

    /// Fetches all open tabs across all running supported browsers silently (no permission prompt).
    func fetchTabs() -> [WindowInfo] {
        fetchTabsResult(promptIfNeeded: false).tabs
    }

    /// Fetches open tabs across running supported browsers, optionally prompting for Automation
    /// permission when invoked explicitly by the user (must be called off the main thread).
    func fetchTabsResult(promptIfNeeded: Bool) -> FetchResult {
        var result: [WindowInfo] = []
        var deniedBrowsers: [String] = []
        let runningApps = NSWorkspace.shared.runningApplications

        for browser in browsers {
            guard let app = runningApps.first(where: {
                $0.bundleIdentifier == browser.bundleID || $0.localizedName == browser.name
            }) else {
                continue
            }

            let targetBundleID = app.bundleIdentifier ?? browser.bundleID
            let permStatus = Permissions.automationPermission(
                forBundleID: targetBundleID,
                askUserIfNeeded: promptIfNeeded
            )
            if permStatus == OSStatus(errAEEventNotPermitted) {
                deniedBrowsers.append(browser.name)
                continue
            }
            if !promptIfNeeded && permStatus == OSStatus(errAEEventWouldRequireUserConsent) {
                continue
            }

            let (tabs, deniedByScript) = queryTabs(for: browser, pid: app.processIdentifier)
            if deniedByScript {
                deniedBrowsers.append(browser.name)
            } else {
                result.append(contentsOf: tabs)
            }
        }

        return FetchResult(tabs: result, deniedBrowsers: deniedBrowsers)
    }

    private func compiledTabScript(for browser: SupportedBrowser) -> NSAppleScript? {
        if let existing = compiledTabScripts[browser.bundleID] {
            return existing
        }
        let titleProperty = browser.kind == .safari ? "name" : "title"
        let scriptSource = """
        set fieldSep to ASCII character 31
        set rowSep to ASCII character 30
        tell application "\(browser.name)"
            set output to ""
            try
                set winCount to count of windows
            on error
                return ""
            end try
            repeat with wIdx from 1 to winCount
                set w to window wIdx
                try
                    set titles to \(titleProperty) of every tab of w
                    set urls to URL of every tab of w
                    set tCount to count of titles
                    set uCount to count of urls
                    if uCount < tCount then set tCount to uCount
                    repeat with tIdx from 1 to tCount
                        set tabTitle to ""
                        set tabURL to ""
                        try
                            set rawTitle to item tIdx of titles
                            if rawTitle is not missing value then set tabTitle to (rawTitle as string)
                        end try
                        try
                            set rawURL to item tIdx of urls
                            if rawURL is not missing value then set tabURL to (rawURL as string)
                        end try
                        set output to output & (wIdx as string) & fieldSep & (tIdx as string) & fieldSep & tabTitle & fieldSep & tabURL & rowSep
                    end repeat
                on error
                    set tIdx to 0
                    try
                        set tabList to tabs of w
                    on error
                        set tabList to {}
                    end try
                    repeat with t in tabList
                        set tIdx to tIdx + 1
                        set tabTitle to ""
                        set tabURL to ""
                        try
                            set rawTitle to \(titleProperty) of t
                            if rawTitle is not missing value then set tabTitle to (rawTitle as string)
                        end try
                        try
                            set rawURL to URL of t
                            if rawURL is not missing value then set tabURL to (rawURL as string)
                        end try
                        set output to output & (wIdx as string) & fieldSep & (tIdx as string) & fieldSep & tabTitle & fieldSep & tabURL & rowSep
                    end repeat
                end try
            end repeat
            return output
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var compileErr: NSDictionary?
        script.compileAndReturnError(&compileErr)
        compiledTabScripts[browser.bundleID] = script
        return script
    }

    private func queryTabs(for browser: SupportedBrowser, pid: pid_t) -> (tabs: [WindowInfo], permissionDenied: Bool) {
        var error: NSDictionary?
        let descriptor: NSAppleEventDescriptor? = scriptQueue.sync {
            guard let script = compiledTabScript(for: browser) else { return nil }
            return script.executeAndReturnError(&error)
        }
        if let error, let code = error[NSAppleScript.errorNumber] as? Int, code == Int(errAEEventNotPermitted) {
            return ([], true)
        }
        guard let output = descriptor?.stringValue, !output.isEmpty else { return ([], false) }

        var items: [WindowInfo] = []
        let entries = output.components(separatedBy: "\u{1E}")

        for entry in entries where !entry.isEmpty {
            let parts = entry.components(separatedBy: "\u{1F}")
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

        return (items, false)
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
