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
    private let cacheTTL: TimeInterval = 4.0
    private let ttl: TimeInterval = 2.0

    nonisolated var permissionGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    var lastCaptureSucceeded: Bool { content != nil }

    @discardableResult
    func refresh() async -> Bool {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < ttl {
            return true
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            var map: [CGWindowID: SCWindow] = [:]
            map.reserveCapacity(content.windows.count)
            for window in content.windows where window.windowLayer == 0 {
                map[window.windowID] = window
            }
            self.content = content
            self.windowsByID = map
            self.fetchedAt = Date()
            return true
        } catch {
            self.content = nil
            self.windowsByID = [:]
            self.fetchedAt = nil
            return false
        }
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

        guard await refresh() else { return nil }
        guard let window = windowsByID[windowID] else { return nil }

        let fitted = aspectFittedPixelSize(windowFrame: window.frame, maxSize: pixelSize)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = fitted.width
        config.height = fitted.height
        config.showsCursor = false
        config.scalesToFit = true

        let image: CGImage? = await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
                continuation.resume(returning: image)
            }
        }
        if let image {
            let ratio = window.frame.height > 0 ? (window.frame.width / window.frame.height) : 1.6
            thumbnailCache[key] = (image, ratio, now)
        }
        return image
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
