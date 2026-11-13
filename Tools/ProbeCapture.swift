//
//  Development helper: exercises the exact ScreenCaptureKit capture path
//  TabStation uses, so API misuse shows up as a distinct error rather than a
//  silent fallback to icons.
//
//  Usage: swift Tools/ProbeCapture.swift
//

import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

_ = NSApplication.shared

func line(_ s: String) { print(s) }

let preflight = CGPreflightScreenCaptureAccess()
line("CGPreflightScreenCaptureAccess() -> \(preflight)")

let content: SCShareableContent
do {
    content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    line("SCShareableContent: \(content.windows.count) windows, \(content.displays.count) displays")
} catch {
    line("SCShareableContent FAILED -> \(error.localizedDescription)")
    line("(this is expected without Screen Recording permission)")
    exit(0)
}

guard let window = content.windows.first(where: { $0.windowLayer == 0 && $0.frame.width > 200 }) else {
    line("no suitable window to capture")
    exit(0)
}
line("target window id=\(window.windowID) title=\(window.title ?? "<redacted>") frame=\(window.frame)")

let filter = SCContentFilter(desktopIndependentWindow: window)
let config = SCStreamConfiguration()
config.width = 312
config.height = 156
config.showsCursor = false
config.scalesToFit = true

let image: CGImage? = await withCheckedContinuation { continuation in
    SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
        if let error { line("captureImage FAILED -> \(error.localizedDescription)") }
        continuation.resume(returning: image)
    }
}

if let image {
    line("captureImage OK -> \(image.width)x\(image.height) px")
    let out = URL(fileURLWithPath: "/tmp/tabstation-probe-capture.png")
    if let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        line("wrote \(out.path)")
    }
} else {
    line("captureImage returned nil")
}