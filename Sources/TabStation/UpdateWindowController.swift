import AppKit

/// Clean native macOS software update window displaying release notes,
/// download progress, and one-click Install & Relaunch for end users.
final class UpdateWindowController: NSWindowController {

    private var release: ReleaseInfo?

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let notesView = NSTextView()
    private let progressBar = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")

    private var skipButton = NSButton(title: "", target: nil, action: nil)
    private var githubButton = NSButton(title: "", target: nil, action: nil)
    private var laterButton = NSButton(title: "", target: nil, action: nil)
    private var installButton = NSButton(title: "", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 356),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        self.init(window: window)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateChanged),
            name: .altDeckUpdateStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: .tabStationAppearanceChanged,
            object: nil
        )
        buildUI()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show(release: ReleaseInfo) {
        self.release = release
        buildUI()
        applyState()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildUI() {
        guard let window else { return }
        window.title = L10n.t("AltDeck Software Update", "AltDeck 软件更新")

        let root = NSView(frame: window.contentRect(forFrameRect: window.frame))
        root.wantsLayer = true

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 48).isActive = true

        titleLabel.font = .systemFont(ofSize: 15.5, weight: .bold)
        titleLabel.textColor = .labelColor

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        let headerText = NSStackView(views: [titleLabel, subtitleLabel])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 3

        let headerRow = NSStackView(views: [iconView, headerText])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 14
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        let notesScroll = NSScrollView()
        notesScroll.hasVerticalScroller = true
        notesScroll.hasHorizontalScroller = false
        notesScroll.autohidesScrollers = true
        notesScroll.borderType = .bezelBorder
        notesScroll.translatesAutoresizingMaskIntoConstraints = false
        notesScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        notesView.isEditable = false
        notesView.isSelectable = true
        notesView.drawsBackground = true
        notesView.backgroundColor = .textBackgroundColor
        notesView.textContainerInset = NSSize(width: 8, height: 8)
        notesView.font = .systemFont(ofSize: 12)
        notesView.textColor = .labelColor
        notesView.isVerticallyResizable = true
        notesView.isHorizontallyResizable = false
        notesView.autoresizingMask = [.width]
        notesView.textContainer?.widthTracksTextView = true
        notesScroll.documentView = notesView

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.isHidden = true
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isHidden = true

        skipButton = NSButton(
            title: L10n.t("Skip This Version", "跳过此版本"),
            target: self,
            action: #selector(skipClicked)
        )
        skipButton.bezelStyle = .rounded

        githubButton = NSButton(
            title: L10n.t("View on GitHub", "在 GitHub 查看"),
            target: self,
            action: #selector(githubClicked)
        )
        githubButton.bezelStyle = .rounded

        laterButton = NSButton(
            title: L10n.t("Later", "稍后提醒"),
            target: self,
            action: #selector(laterClicked)
        )
        laterButton.bezelStyle = .rounded

        installButton = NSButton(
            title: L10n.t("Install & Relaunch", "立即更新并重启"),
            target: self,
            action: #selector(installClicked)
        )
        installButton.bezelStyle = .rounded
        installButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let footerRow = NSStackView(views: [skipButton, githubButton, spacer, laterButton, installButton])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 8
        footerRow.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [headerRow, notesScroll, progressBar, statusLabel, footerRow])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            headerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            notesScroll.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            progressBar.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            footerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])

        window.contentView = root
    }

    private func applyState() {
        let rel = release ?? UpdateManager.shared.availableRelease
        let current = UpdateManager.shared.currentVersion

        if let rel {
            titleLabel.stringValue = L10n.t(
                "A New Version of AltDeck is Available!",
                "发现 AltDeck 新版本！"
            )
            subtitleLabel.stringValue = L10n.t(
                "AltDeck v\(rel.version) is available — you currently have v\(current).",
                "最新版本 v\(rel.version) 已发布（当前版本：v\(current)）。"
            )
            notesView.string = rel.releaseNotes.isEmpty
                ? L10n.t("Bug fixes and performance improvements.", "问题修复与性能优化。")
                : rel.releaseNotes
        }

        switch UpdateManager.shared.state {
        case .downloading(_, let progress, let received, let expected):
            progressBar.isHidden = false
            progressBar.isIndeterminate = (expected <= 0)
            if expected > 0 {
                progressBar.doubleValue = progress
                let recvMB = String(format: "%.1f", Double(received) / 1_048_576.0)
                let expMB = String(format: "%.1f", Double(expected) / 1_048_576.0)
                statusLabel.stringValue = L10n.t(
                    "Downloading update… \(recvMB) / \(expMB) MB",
                    "正在下载更新… \(recvMB) / \(expMB) MB"
                )
            } else {
                statusLabel.stringValue = L10n.t("Downloading update…", "正在下载更新…")
            }
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.isHidden = false
            skipButton.isEnabled = false
            laterButton.title = L10n.t("Cancel Download", "取消下载")
            installButton.isEnabled = false
            installButton.title = L10n.t("Downloading…", "下载中…")

        case .installing:
            progressBar.isHidden = false
            progressBar.isIndeterminate = true
            progressBar.startAnimation(nil)
            statusLabel.stringValue = L10n.t(
                "Verifying Apple signature and installing… AltDeck will relaunch automatically.",
                "正在校验签名并覆盖安装…完成后将自动重启 AltDeck。"
            )
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.isHidden = false
            skipButton.isEnabled = false
            laterButton.isEnabled = false
            installButton.isEnabled = false
            installButton.title = L10n.t("Installing…", "安装中…")

        case .error(let msg):
            progressBar.stopAnimation(nil)
            progressBar.isHidden = true
            statusLabel.stringValue = L10n.t("Update failed: \(msg)", "更新失败：\(msg)")
            statusLabel.textColor = .systemRed
            statusLabel.isHidden = false
            skipButton.isEnabled = true
            laterButton.isEnabled = true
            laterButton.title = L10n.t("Close", "关闭")
            installButton.isEnabled = true
            installButton.title = L10n.t("Retry Update", "重试更新")

        default:
            progressBar.stopAnimation(nil)
            progressBar.isHidden = true
            statusLabel.isHidden = true
            skipButton.isEnabled = true
            laterButton.isEnabled = true
            laterButton.title = L10n.t("Later", "稍后提醒")
            installButton.isEnabled = true
            installButton.title = (rel?.zipDownloadURL != nil)
                ? L10n.t("Install & Relaunch", "立即更新并重启")
                : L10n.t("Download Release", "前往下载新版")
        }
    }

    @objc private func stateChanged() {
        applyState()
    }

    @objc private func appearanceChanged() {
        if release != nil {
            buildUI()
            applyState()
        }
    }

    @objc private func skipClicked() {
        UpdateManager.shared.skipAvailableRelease()
    }

    @objc private func githubClicked() {
        let url = release?.htmlURL ?? UpdateManager.releasesPageURL
        NSWorkspace.shared.open(url)
    }

    @objc private func laterClicked() {
        if case .downloading = UpdateManager.shared.state {
            UpdateManager.shared.cancelDownload()
        } else {
            close()
        }
    }

    @objc private func installClicked() {
        UpdateManager.shared.startInstall()
    }
}
