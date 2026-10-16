// SPDX-License-Identifier: MIT
// Generates EveryTMP's .iconset (thermometer on a dark rounded square).
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit
import CoreGraphics

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make-icon.swift <output.iconset>\n", stderr)
    exit(1)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> CGImage? {
    let width = Int(size)
    let height = Int(size)
    guard let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    let scale = size / 1024.0

    // Background: dark rounded square with a subtle vertical gradient.
    let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
    let bgPath = CGPath(
        roundedRect: bgRect.insetBy(dx: 40 * scale, dy: 40 * scale),
        cornerWidth: 220 * scale, cornerHeight: 220 * scale, transform: nil
    )
    context.addPath(bgPath)
    context.clip()
    let top = NSColor(red: 0.24, green: 0.24, blue: 0.27, alpha: 1.0).cgColor
    let bottom = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0).cgColor
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [top, bottom] as CFArray,
        locations: [0.0, 1.0]
    ) else { return nil }
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: []
    )

    // Thermometer tube (light) + bulb (light).
    let tubeColor = NSColor(white: 0.94, alpha: 1.0).cgColor
    let mercuryColor = NSColor(red: 1.0, green: 0.32, blue: 0.24, alpha: 1.0).cgColor
    let cx = size / 2.0

    // Bulb.
    let bulbRadius = 165 * scale
    let bulbCenter = CGPoint(x: cx, y: 300 * scale)
    context.setFillColor(tubeColor)
    context.fillEllipse(in: CGRect(
        x: bulbCenter.x - bulbRadius, y: bulbCenter.y - bulbRadius,
        width: bulbRadius * 2, height: bulbRadius * 2
    ))

    // Tube: rounded rect from the bulb up.
    let tubeWidth = 120 * scale
    let tubeRect = CGRect(
        x: cx - tubeWidth / 2, y: bulbCenter.y,
        width: tubeWidth, height: 560 * scale
    )
    context.setFillColor(tubeColor)
    context.fillEllipse(in: CGRect(
        x: tubeRect.minX, y: tubeRect.maxY - tubeWidth,
        width: tubeWidth, height: tubeWidth
    ))
    context.fill(tubeRect)

    // Mercury: inner bulb + inner tube (about 60% full).
    let innerBulb = bulbRadius * 0.62
    context.setFillColor(mercuryColor)
    context.fillEllipse(in: CGRect(
        x: bulbCenter.x - innerBulb, y: bulbCenter.y - innerBulb,
        width: innerBulb * 2, height: innerBulb * 2
    ))
    let innerWidth = tubeWidth * 0.45
    context.fill(CGRect(
        x: cx - innerWidth / 2, y: bulbCenter.y,
        width: innerWidth, height: 330 * scale
    ))
    context.fillEllipse(in: CGRect(
        x: cx - innerWidth / 2, y: bulbCenter.y + 330 * scale - innerWidth,
        width: innerWidth, height: innerWidth
    ))

    // Tick marks (°C scale hint) on the right of the tube.
    context.setStrokeColor(NSColor(white: 0.94, alpha: 1.0).cgColor)
    context.setLineWidth(max(2.0, 8 * scale))
    for i in 0..<4 {
        let y = bulbCenter.y + CGFloat(120 + i * 110) * scale
        context.move(to: CGPoint(x: cx + 110 * scale, y: y))
        context.addLine(to: CGPoint(x: cx + (i == 3 ? 200 : 160) * scale, y: y))
        context.strokePath()
    }

    return context.makeImage()
}

// Standard macOS iconset sizes.
let specs: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for spec in specs {
    guard let image = drawIcon(size: spec.pixels) else {
        fputs("failed to draw \(spec.name)\n", stderr)
        exit(1)
    }
    let destURL = outDir.appendingPathComponent("\(spec.name).png")
    guard let dest = CGImageDestinationCreateWithURL(
        destURL as CFURL, "public.png" as CFString, 1, nil
    ) else {
        fputs("failed to create \(spec.name)\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        fputs("failed to write \(spec.name)\n", stderr)
        exit(1)
    }
}
print("wrote \(specs.count) files to \(outDir.path)")
