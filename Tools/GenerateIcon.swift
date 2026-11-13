//
//  Generates TabStation's .iconset from pure CoreGraphics — no AppKit window
//  server needed, so it works from a build script.
//
//  Usage: swift Tools/GenerateIcon.swift <output.iconset dir>
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "./AppIcon.iconset"

try FileManager.default.createDirectory(
    atPath: outputPath,
    withIntermediateDirectories: true
)

let colorSpace = CGColorSpaceCreateDeviceRGB()

func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Draws the icon at `size`×`size` points: a blue squircle with two offset
/// window cards, echoing the app's own switcher.
func renderIcon(size: Int) -> CGImage? {
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let s = CGFloat(size)
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // Background squircle.
    let background = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
        cornerWidth: s * 0.2236,
        cornerHeight: s * 0.2236,
        transform: nil
    )
    ctx.saveGState()
    ctx.addPath(background)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgba(0.36, 0.56, 1.0), rgba(0.18, 0.31, 0.86)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: s),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
    ctx.restoreGState()

    func card(_ rect: CGRect, opacity: Double) {
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.012),
            blur: s * 0.035,
            color: rgba(0, 0, 0, 0.32 * opacity)
        )
        ctx.setFillColor(rgba(1, 1, 1, opacity))
        ctx.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: s * 0.062,
            cornerHeight: s * 0.062,
            transform: nil
        ))
        ctx.fillPath()
        ctx.restoreGState()
    }

    card(CGRect(x: s * 0.195, y: s * 0.295, width: s * 0.41, height: s * 0.41), opacity: 0.55)
    card(CGRect(x: s * 0.395, y: s * 0.215, width: s * 0.41, height: s * 0.41), opacity: 1)

    return ctx.makeImage()
}

func write(_ image: CGImage, to name: String) {
    let url = URL(fileURLWithPath: outputPath).appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for (points, scale) in variants {
    let pixels = points * scale
    guard let image = renderIcon(size: pixels) else {
        FileHandle.standardError.write(Data("failed to render \(pixels)px\n".utf8))
        exit(1)
    }
    let name = scale == 1
        ? "icon_\(points)x\(points).png"
        : "icon_\(points)x\(points)@2x.png"
    write(image, to: name)
}

print("Wrote \(variants.count) icon variants to \(outputPath)")