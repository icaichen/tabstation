import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Captures crisp, aspect-accurate window images via ScreenCaptureKit.
actor ThumbnailService {
    static let shared = ThumbnailService()

    enum ResolutionTier: Hashable {
        case thumbnail
        case preview
    }

    private struct CacheKey: Hashable {
        let windowID: CGWindowID
        let tier: ResolutionTier
    }

    private var content: SCShareableContent?
    private var fetchedAt: Date?
    private var windowsByID: [CGWindowID: SCWindow] = [:]
    private var thumbnailCache: [CacheKey: (image: CGImage, aspectRatio: CGFloat, timestamp: TimeInterval)] = [:]
    private var staleCache: [CGWindowID: CGImage] = [:]
    private var inFlightRefresh: Task<Bool, Never>?
    private let cacheTTL: TimeInterval = 6.0
    private let ttl: TimeInterval = 2.5

    nonisolated var permissionGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    var lastCaptureSucceeded: Bool { content != nil }

    @discardableResult
    func refresh(force: Bool = false) async -> Bool {
        if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < ttl, content != nil {
            return true
        }
        if let existing = inFlightRefresh {
            return await existing.value
        }
        let task = Task<Bool, Never> {
            do {
                let freshContent = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                var map: [CGWindowID: SCWindow] = [:]
                map.reserveCapacity(freshContent.windows.count)
                for window in freshContent.windows where window.windowLayer == 0 {
                    map[window.windowID] = window
                }
                self.setRefreshedContent(freshContent, map: map)
                return true
            } catch {
                self.clearRefreshedContent()
                return false
            }
        }
        inFlightRefresh = task
        let result = await task.value
        inFlightRefresh = nil
        return result
    }

    private func setRefreshedContent(_ freshContent: SCShareableContent, map: [CGWindowID: SCWindow]) {
        self.content = freshContent
        self.windowsByID = map
        self.fetchedAt = Date()
    }

    private func clearRefreshedContent() {
        self.content = nil
        self.windowsByID = [:]
        self.fetchedAt = nil
    }

    /// Resolves the live ScreenCaptureKit window handle for a `WindowInfo`.
    /// When a virtual item (such as a browser tab ID) is passed, falls back to a
    /// real layer-0 window owned by the same process.
    func shareableWindow(for window: WindowInfo) async -> SCWindow? {
        guard await refresh() else { return nil }
        if window.id > 0, (window.id & 0xFF00_0000) != 0x7F00_0000, let exact = windowsByID[window.id] {
            return exact
        }
        let pidWindows = windowsByID.values.filter { $0.owningApplication?.processID == window.pid }
        if let titleMatched = pidWindows.first(where: { !$0.title.isNilOrEmpty && window.title.localizedCaseInsensitiveContains($0.title ?? "") }) {
            return titleMatched
        }
        return pidWindows.max { lhs, rhs in
            (lhs.frame.width * lhs.frame.height) < (rhs.frame.width * rhs.frame.height)
        }
    }

    /// Fast cache-only lookup for instant warm rendering when opening the switcher.
    func cachedThumbnail(windowID: CGWindowID, tier: ResolutionTier = .thumbnail) -> CGImage? {
        guard windowID > 0 else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        let key = CacheKey(windowID: windowID, tier: tier)
        if let cached = thumbnailCache[key], now - cached.timestamp < cacheTTL {
            return cached.image
        }
        return nil
    }

    /// Captures one window fitting within `pixelSize`, strictly preserving the
    /// window's real ScreenCaptureKit aspect ratio to prevent black letterbox bars.
    func thumbnail(
        windowID: CGWindowID,
        pixelSize: CGSize,
        tier: ResolutionTier = .thumbnail
    ) async -> CGImage? {
        guard windowID > 0 else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        let key = CacheKey(windowID: windowID, tier: tier)
        if let cached = thumbnailCache[key], now - cached.timestamp < cacheTTL {
            return cached.image
        }

        guard await refresh() else { return staleCache[windowID] }
        if windowsByID[windowID] == nil,
           let fetchedAt, Date().timeIntervalSince(fetchedAt) > 0.25 {
            _ = await refresh(force: true)
        }
        guard let window = windowsByID[windowID] else { return staleCache[windowID] }

        let fitted = aspectFittedPixelSize(windowFrame: window.frame, maxSize: pixelSize)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = fitted.width
        config.height = fitted.height
        config.showsCursor = false
        config.scalesToFit = true

        let image = await captureImageWithTimeout(filter: filter, configuration: config, timeoutNanoseconds: 1_500_000_000)
        if let image {
            let ratio = window.frame.height > 0 ? (window.frame.width / window.frame.height) : 1.6
            thumbnailCache[key] = (image, ratio, now)
            staleCache[windowID] = image
            return image
        }
        return staleCache[windowID]
    }

    private nonisolated func captureImageWithTimeout(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        timeoutNanoseconds: UInt64
    ) async -> CGImage? {
        final class OnceGate: @unchecked Sendable {
            private let lock = NSLock()
            private var finished = false
            func tryEnter() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return false }
                finished = true
                return true
            }
        }

        return await withCheckedContinuation { continuation in
            let gate = OnceGate()
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
                if gate.tryEnter() {
                    continuation.resume(returning: image)
                }
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .nanoseconds(Int(timeoutNanoseconds))
            ) {
                if gate.tryEnter() {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Computes exact integer pixel bounds matching `windowFrame`'s native aspect ratio.
    private func aspectFittedPixelSize(windowFrame: CGRect, maxSize: CGSize) -> (width: Int, height: Int) {
        let srcW = max(1, windowFrame.width)
        let srcH = max(1, windowFrame.height)
        let targetW = max(64, maxSize.width)
        let targetH = max(64, maxSize.height)
        let scale = min(targetW / srcW, targetH / srcH, 2.0)
        return (
            width: max(64, Int((srcW * scale).rounded())),
            height: max(64, Int((srcH * scale).rounded()))
        )
    }
}

extension CGSize {
    var isUsable: Bool { width >= 1 && height >= 1 }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
