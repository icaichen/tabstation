import AppKit
import Foundation

extension Notification.Name {
    static let altDeckUpdateStateChanged = Notification.Name("AltDeck.updateStateChanged")
}

/// Parses and compares dot-separated semantic versions such as "v1.0.1" or "1.2.0".
struct SemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let isPrerelease: Bool

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = (trimmed.hasPrefix("v") || trimmed.hasPrefix("V"))
            ? String(trimmed.dropFirst())
            : trimmed
        let parts = withoutPrefix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = String(parts[0])
        let prerelease = parts.count > 1 && !parts[1].isEmpty
        let nums = core.split(separator: ".").compactMap { Int($0) }
        guard !nums.isEmpty else { return nil }

        self.major = nums[0]
        self.minor = nums.count > 1 ? nums[1] : 0
        self.patch = nums.count > 2 ? nums[2] : 0
        self.isPrerelease = prerelease
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        return lhs.isPrerelease && !rhs.isPrerelease
    }

    static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        guard let r = SemanticVersion(remote), let l = SemanticVersion(local) else {
            return false
        }
        return r > l
    }
}

/// Metadata extracted from a GitHub Release response.
struct ReleaseInfo: Equatable {
    let version: String
    let tagName: String
    let title: String
    let releaseNotes: String
    let htmlURL: URL
    let zipDownloadURL: URL?
    let dmgDownloadURL: URL?

    var bestAssetURL: URL {
        zipDownloadURL ?? dmgDownloadURL ?? htmlURL
    }
}

/// Handles periodic background update checks, manual checks, notifications, and
/// verified one-click self-updates from GitHub Releases.
final class UpdateManager: NSObject, URLSessionDownloadDelegate {

    static let shared = UpdateManager()

    private enum Keys {
        static let autoCheck = "AltDeck.autoCheckUpdates"
        static let lastCheckTimestamp = "AltDeck.lastUpdateCheckTimestamp"
        static let skippedVersion = "AltDeck.skippedUpdateVersion"
    }

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/icaichen/tabstation/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/icaichen/tabstation/releases/latest")!
    private static let autoCheckInterval: TimeInterval = 12 * 3600

    enum State: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case updateAvailable(ReleaseInfo)
        case downloading(ReleaseInfo, progress: Double, receivedBytes: Int64, expectedBytes: Int64)
        case installing(ReleaseInfo)
        case error(String)
    }

    private(set) var state: State = .idle {
        didSet {
            NotificationCenter.default.post(name: .altDeckUpdateStateChanged, object: nil)
        }
    }

    private(set) var availableRelease: ReleaseInfo?
    private var periodicTimer: Timer?
    private var notifiedVersionThisRun: String?
    private var activeDownloadTask: URLSessionDownloadTask?
    private var activeDownloadRelease: ReleaseInfo?
    private lazy var downloadSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    }()
    private var updateWindowController: UpdateWindowController?

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.autoCheck) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.autoCheck)
            if newValue {
                schedulePeriodicChecks()
            } else {
                periodicTimer?.invalidate()
                periodicTimer = nil
            }
        }
    }

    var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: Keys.skippedVersion) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.skippedVersion) }
    }

    // MARK: - Scheduling & Checks

    func schedulePeriodicChecks() {
        periodicTimer?.invalidate()
        guard autoCheckEnabled else { return }

        // Delay startup check slightly so launch & permissions flow stay completely snappy.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self, self.autoCheckEnabled else { return }
            let last = UserDefaults.standard.double(forKey: Keys.lastCheckTimestamp)
            let now = Date().timeIntervalSince1970
            if now - last >= Self.autoCheckInterval {
                self.checkForUpdates(userInitiated: false)
            }
        }

        let timer = Timer(timeInterval: Self.autoCheckInterval, repeats: true) { [weak self] _ in
            guard let self, self.autoCheckEnabled else { return }
            self.checkForUpdates(userInitiated: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicTimer = timer
    }

    func checkForUpdatesManually() {
        checkForUpdates(userInitiated: true)
    }

    func checkForUpdates(userInitiated: Bool) {
        if case .downloading = state {
            presentUpdateWindow()
            return
        }
        if case .installing = state {
            presentUpdateWindow()
            return
        }

        state = .checking
        var request = URLRequest(url: Self.latestReleaseAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AltDeck/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleCheckResponse(data: data, response: response, error: error, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func handleCheckResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        userInitiated: Bool
    ) {
        if let error {
            let msg = error.localizedDescription
            state = userInitiated ? .error(msg) : .idle
            if userInitiated {
                presentCheckFailureAlert(detail: msg)
            }
            return
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = "HTTP \(http.statusCode)"
            state = userInitiated ? .error(msg) : .idle
            if userInitiated {
                presentCheckFailureAlert(detail: msg)
            }
            return
        }

        guard let data, let release = Self.decodeLatestRelease(from: data) else {
            let msg = L10n.t("Unable to parse release information.", "无法解析版本更新信息。")
            state = userInitiated ? .error(msg) : .idle
            if userInitiated {
                presentCheckFailureAlert(detail: msg)
            }
            return
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastCheckTimestamp)

        if SemanticVersion.isVersion(release.version, newerThan: currentVersion) {
            availableRelease = release
            state = .updateAvailable(release)

            let isSkipped = (skippedVersion == release.version)
            if userInitiated {
                skippedVersion = nil
                presentUpdateWindow()
            } else if !isSkipped && notifiedVersionThisRun != release.version {
                notifiedVersionThisRun = release.version
                presentUpdateWindow()
            }
        } else {
            availableRelease = nil
            state = .upToDate(version: currentVersion)
            if userInitiated {
                presentUpToDateAlert(latestVersion: release.version)
            }
        }
    }

    /// Parses GitHub's `/releases/latest` JSON payload into a `ReleaseInfo`.
    static func decodeLatestRelease(from data: Data) -> ReleaseInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            return nil
        }
        let version = (tag.hasPrefix("v") || tag.hasPrefix("V")) ? String(tag.dropFirst()) : tag
        guard SemanticVersion(version) != nil else { return nil }

        let title = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (json["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let htmlURL = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPageURL

        var zipURL: URL?
        var dmgURL: URL?
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                guard let name = asset["name"] as? String,
                      let dl = asset["browser_download_url"] as? String,
                      let url = URL(string: dl) else {
                    continue
                }
                let lower = name.lowercased()
                if lower.hasSuffix(".zip") && zipURL == nil {
                    zipURL = url
                } else if lower.hasSuffix(".dmg") && dmgURL == nil {
                    dmgURL = url
                }
            }
        }

        return ReleaseInfo(
            version: version,
            tagName: tag,
            title: (title?.isEmpty == false ? title! : "AltDeck \(tag)"),
            releaseNotes: body,
            htmlURL: htmlURL,
            zipDownloadURL: zipURL,
            dmgDownloadURL: dmgURL
        )
    }

    // MARK: - UI Presentation

    func presentUpdateWindow() {
        guard let release = availableRelease else {
            checkForUpdatesManually()
            return
        }
        if updateWindowController == nil {
            updateWindowController = UpdateWindowController()
        }
        updateWindowController?.show(release: release)
    }

    func skipAvailableRelease() {
        if let release = availableRelease {
            skippedVersion = release.version
        }
        updateWindowController?.close()
    }

    private func presentUpToDateAlert(latestVersion: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.t("You're Up to Date!", "当前已是最新版本")
        alert.informativeText = L10n.t(
            "AltDeck v\(currentVersion) is currently the newest version available.",
            "AltDeck v\(currentVersion) 已是目前发布的最新版本（线上最新：v\(latestVersion)）。"
        )
        alert.addButton(withTitle: L10n.t("OK", "好的"))
        alert.runModal()
    }

    private func presentCheckFailureAlert(detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t("Update Check Failed", "检查更新失败")
        alert.informativeText = L10n.t(
            "Could not reach GitHub Releases (\(detail)). You can check the downloads page manually.",
            "暂时无法连接 GitHub 获取最新版本（\(detail)），你可以稍后重试或直接打开下载页。"
        )
        alert.addButton(withTitle: L10n.t("OK", "确定"))
        alert.addButton(withTitle: L10n.t("Open Releases Page", "打开下载页"))
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(Self.releasesPageURL)
        }
    }

    // MARK: - Download & Install

    func startInstall() {
        guard let release = availableRelease else { return }
        if case .downloading = state { return }
        if case .installing = state { return }

        guard let zipURL = release.zipDownloadURL else {
            NSWorkspace.shared.open(release.dmgDownloadURL ?? release.htmlURL)
            updateWindowController?.close()
            return
        }

        activeDownloadRelease = release
        state = .downloading(release, progress: 0, receivedBytes: 0, expectedBytes: 0)
        let task = downloadSession.downloadTask(with: zipURL)
        activeDownloadTask = task
        task.resume()
    }

    func cancelDownload() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        if let release = activeDownloadRelease ?? availableRelease {
            state = .updateAvailable(release)
        } else {
            state = .idle
        }
        activeDownloadRelease = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let release = activeDownloadRelease ?? availableRelease else { return }
        let ratio = totalBytesExpectedToWrite > 0
            ? min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
            : 0.0
        state = .downloading(
            release,
            progress: ratio,
            receivedBytes: totalBytesWritten,
            expectedBytes: totalBytesExpectedToWrite
        )
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let release = activeDownloadRelease ?? availableRelease else { return }
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("altdeck-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            let zipDest = stagingDir.appendingPathComponent("AltDeck-update.zip")
            try FileManager.default.moveItem(at: location, to: zipDest)
            activeDownloadTask = nil
            state = .installing(release)

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.extractVerifyAndReplace(zipURL: zipDest, stagingDir: stagingDir, release: release)
            }
        } catch {
            activeDownloadTask = nil
            state = .error(error.localizedDescription)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        activeDownloadTask = nil
        if let release = activeDownloadRelease ?? availableRelease {
            state = .error(error.localizedDescription)
            _ = release
        } else {
            state = .error(error.localizedDescription)
        }
    }

    private func extractVerifyAndReplace(zipURL: URL, stagingDir: URL, release: ReleaseInfo) {
        let extractDir = stagingDir.appendingPathComponent("extracted", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        } catch {
            finishInstallWithError(error.localizedDescription, cleanupDir: stagingDir)
            return
        }

        // 1. Unzip preserving macOS symlinks and resource forks via ditto
        let dittoStatus = runTool("/usr/bin/ditto", args: ["-x", "-k", zipURL.path, extractDir.path])
        guard dittoStatus == 0 else {
            finishInstallWithError(L10n.t("Failed to extract downloaded archive.", "更新包解压失败。"), cleanupDir: stagingDir)
            return
        }

        // 2. Locate AltDeck.app inside extracted directory
        guard let extractedApp = findAppBundle(in: extractDir) else {
            finishInstallWithError(L10n.t("AltDeck.app was not found inside the update archive.", "更新包中未找到 AltDeck.app。"), cleanupDir: stagingDir)
            return
        }

        // 3. Verify strict code signature, bundle identifier, and Team ID (when Developer-ID signed)
        let verifyStatus = runTool("/usr/bin/codesign", args: ["--verify", "--deep", "--strict", extractedApp.path])
        let newBundleID = Bundle(url: extractedApp)?.bundleIdentifier
        let expectedBundleID = Bundle.main.bundleIdentifier ?? "com.tabstation.TabStation"
        let currentTeamID = codesignTeamIdentifier(for: Bundle.main.bundleURL)
        let candidateTeamID = codesignTeamIdentifier(for: extractedApp)
        let teamMatches: Bool = {
            guard let currentTeamID, !currentTeamID.isEmpty, currentTeamID != "not set" else {
                return true
            }
            return candidateTeamID == currentTeamID
        }()
        guard verifyStatus == 0, newBundleID == expectedBundleID, teamMatches else {
            finishInstallWithError(
                L10n.t("Update signature verification failed. Please download directly from GitHub.", "更新包签名校验未通过，为安全起见已取消自动覆盖，请前往 GitHub 手动下载。"),
                cleanupDir: stagingDir
            )
            return
        }

        // 4. Determine install destination (if launched from read-only DMG/translocation, install into /Applications)
        let targetApp = resolveInstallTarget()
        let parentDir = targetApp.deletingLastPathComponent()
        let needsElevation = !FileManager.default.isWritableFile(atPath: parentDir.path)
            || (FileManager.default.fileExists(atPath: targetApp.path) && !FileManager.default.isWritableFile(atPath: targetApp.path))

        if needsElevation {
            let shellCmd = """
            rm -rf '\(targetApp.path).bak' && \
            ([ ! -d '\(targetApp.path)' ] || mv '\(targetApp.path)' '\(targetApp.path).bak') && \
            /usr/bin/ditto '\(extractedApp.path)' '\(targetApp.path)' && \
            (/usr/bin/xattr -dr com.apple.quarantine '\(targetApp.path)' 2>/dev/null || true) && \
            rm -rf '\(targetApp.path).bak'
            """
            let escaped = shellCmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            DispatchQueue.main.async { [weak self] in
                var errDict: NSDictionary?
                let script = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")
                let ok = script?.executeAndReturnError(&errDict) != nil
                try? FileManager.default.removeItem(at: stagingDir)
                if ok {
                    NSWorkspace.shared.openApplication(at: targetApp, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                        DispatchQueue.main.async { NSApp.terminate(nil) }
                    }
                } else {
                    self?.state = .updateAvailable(release)
                }
            }
            return
        }

        // Standard user-writable replacement: wait for current PID exit, swap atomically, relaunch.
        // If replacement fails (e.g., macOS App Management permission denied), restore backup, relaunch current app,
        // and reveal the verified new AltDeck.app in Finder so the user is never stranded.
        let scriptURL = stagingDir.appendingPathComponent("relaunch-update.sh")
        let helperScript = """
        #!/bin/sh
        PID="$1"
        SRC="$2"
        DST="$3"
        STAGE="$4"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.12; done
        rm -rf "${DST}.bak"
        REPLACED=0
        if [ -d "$DST" ]; then
          if mv "$DST" "${DST}.bak" 2>/dev/null; then
            if /usr/bin/ditto "$SRC" "$DST" 2>/dev/null; then
              REPLACED=1
            else
              [ -d "${DST}.bak" ] && mv "${DST}.bak" "$DST" 2>/dev/null
            fi
          fi
        else
          if /usr/bin/ditto "$SRC" "$DST" 2>/dev/null; then
            REPLACED=1
          fi
        fi
        if [ "$REPLACED" -eq 1 ]; then
          /usr/bin/xattr -dr com.apple.quarantine "$DST" 2>/dev/null || true
          rm -rf "${DST}.bak"
          /usr/bin/open -n "$DST"
          rm -rf "$STAGE"
        else
          /usr/bin/open -n "$DST" 2>/dev/null || true
          /usr/bin/open -R "$SRC" 2>/dev/null || true
        fi
        """
        do {
            try helperScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                scriptURL.path,
                String(ProcessInfo.processInfo.processIdentifier),
                extractedApp.path,
                targetApp.path,
                stagingDir.path
            ]
            try process.run()

            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        } catch {
            finishInstallWithError(error.localizedDescription, cleanupDir: stagingDir)
        }
    }

    private func resolveInstallTarget() -> URL {
        let currentURL = Bundle.main.bundleURL
        let path = currentURL.path
        if path.hasSuffix(".app")
            && !path.hasPrefix("/Volumes/")
            && !path.contains("AppTranslocation") {
            return currentURL
        }
        return URL(fileURLWithPath: "/Applications/AltDeck.app")
    }

    private func findAppBundle(in directory: URL) -> URL? {
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            if let direct = contents.first(where: { $0.pathExtension == "app" }) {
                return direct
            }
            for sub in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue {
                    if let nested = try? FileManager.default.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
                       let found = nested.first(where: { $0.pathExtension == "app" }) {
                        return found
                    }
                }
            }
        }
        return nil
    }

    private func codesignTeamIdentifier(for appURL: URL) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        proc.arguments = ["-dvv", appURL.path]
        let errPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = errPipe
        do {
            try proc.run()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0,
                  let text = String(data: errData, encoding: .utf8)
            else { return nil }
            for line in text.split(separator: "\n") {
                if line.hasPrefix("TeamIdentifier=") {
                    return String(line.dropFirst("TeamIdentifier=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private func runTool(_ path: String, args: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus
        } catch {
            return -1
        }
    }

    private func finishInstallWithError(_ message: String, cleanupDir: URL) {
        try? FileManager.default.removeItem(at: cleanupDir)
        DispatchQueue.main.async { [weak self] in
            self?.state = .error(message)
        }
    }
}
