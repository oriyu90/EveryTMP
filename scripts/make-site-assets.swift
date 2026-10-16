// SPDX-License-Identifier: MIT
// Generates the studio-rizi project site assets (icons + OG image).
// Usage: swift scripts/make-site-assets.swift <output-dir>

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(width: Int, height: Int) -> CGContext? {
    CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

/// Draws the thermometer mark: light tube + bulb with orange mercury.
/// Design canvas: bulb radius 165, tube width 120 on a 1024 grid.
func drawThermometerMark(_ ctx: CGContext, size: CGFloat, cx: CGFloat, cy: CGFloat) {
    let unit: CGFloat = size / 1024
    let tube = color(245, 245, 247)
    let mercury = color(255, 106, 0)
    // Bulb.
    let bulbR = 165 * unit
    ctx.setFillColor(tube)
    ctx.fillEllipse(in: CGRect(
        x: cx - bulbR, y: cy - 300 * unit - bulbR,
        width: bulbR * 2, height: bulbR * 2
    ))
    // Tube.
    let tubeW = 120 * unit
    let tubeRect = CGRect(
        x: cx - tubeW / 2, y: cy - 300 * unit,
        width: tubeW, height: 560 * unit
    )
    ctx.fill(tubeRect)
    ctx.fillEllipse(in: CGRect(
        x: tubeRect.minX, y: tubeRect.maxY - tubeW,
        width: tubeW, height: tubeW
    ))
    // Mercury.
    let innerBulb = bulbR * 0.62
    ctx.setFillColor(mercury)
    ctx.fillEllipse(in: CGRect(
        x: cx - innerBulb, y: cy - 300 * unit - innerBulb,
        width: innerBulb * 2, height: innerBulb * 2
    ))
    let innerW = tubeW * 0.45
    ctx.fill(CGRect(
        x: cx - innerW / 2, y: cy - 300 * unit,
        width: innerW, height: 330 * unit
    ))
    ctx.fillEllipse(in: CGRect(
        x: cx - innerW / 2, y: cy - 300 * unit + 330 * unit - innerW,
        width: innerW, height: innerW
    ))
}

func textWidth(_ text: String, size: CGFloat) -> CGFloat {
    let font = CTFontCreateWithName("Helvetica Neue Bold" as CFString, size, nil)
    let attributes: [CFString: Any] = [kCTFontAttributeName: font]
    let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributed)
    return CTLineGetTypographicBounds(line, nil, nil, nil)
}

func drawText(_ ctx: CGContext, _ text: String, size: CGFloat, color: CGColor, x: CGFloat, y: CGFloat) {
    let font = CTFontCreateWithName("Helvetica Neue Bold" as CFString, size, nil)
    let attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color,
    ]
    let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributed)
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

func writePNG(_ image: CGImage, url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        throw NSError(domain: "assets", code: 1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "assets", code: 2)
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: make-site-assets.swift <output-dir>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func renderIcon(_ px: Int) throws -> CGImage {
    guard let ctx = makeContext(width: px, height: px) else {
        throw NSError(domain: "assets", code: 3)
    }
    let plate = CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px))
    let path = CGPath(
        roundedRect: plate, cornerWidth: CGFloat(px) * 0.22,
        cornerHeight: CGFloat(px) * 0.22, transform: nil
    )
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [color(66, 66, 72), color(22, 22, 26)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: CGFloat(px)),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
    drawThermometerMark(ctx, size: CGFloat(px) * 0.72, cx: CGFloat(px) / 2, cy: CGFloat(px) / 2)
    guard let image = ctx.makeImage() else {
        throw NSError(domain: "assets", code: 4)
    }
    return image
}

for (name, px) in [("favicon-32.png", 32), ("icon-192.png", 192), ("icon-512.png", 512)] {
    try writePNG(try renderIcon(px), url: outDir.appendingPathComponent(name))
    print("wrote \(name)")
}

// OG image (1200x630): centered layout, no overflow.
if let ctx = makeContext(width: 1200, height: 630) {
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [color(52, 52, 58), color(16, 16, 20)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 630),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    let titleSize: CGFloat = 104
    let titleWidth = textWidth("EveryTMP", size: titleSize)
    drawText(
        ctx, "EveryTMP", size: titleSize,
        color: color(245, 245, 247), x: (1200 - titleWidth) / 2, y: 360
    )

    drawThermometerMark(ctx, size: 150, cx: 600, cy: 545)

    let sub1 = "CPU/GPU temperature in your menu bar"
    let sub2 = "Lightweight · Apple Silicon · xx°C at a glance"
    let subSize: CGFloat = 42
    for (text, y) in [(sub1, 262.0), (sub2, 202.0)] {
        let width = textWidth(text, size: subSize)
        drawText(
            ctx, text, size: subSize,
            color: color(255, 159, 10), x: (1200 - width) / 2, y: CGFloat(y)
        )
    }

    let credit = "by Yuki_Orita · Studio RIZI"
    let creditSize: CGFloat = 30
    let creditWidth = textWidth(credit, size: creditSize)
    drawText(
        ctx, credit, size: creditSize,
        color: color(245, 245, 247, 0.75), x: (1200 - creditWidth) / 2, y: 100
    )

    if let image = ctx.makeImage() {
        try writePNG(image, url: outDir.appendingPathComponent("og-image.png"))
        print("wrote og-image.png")
    }
}
