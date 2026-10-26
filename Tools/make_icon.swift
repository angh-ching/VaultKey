import AppKit
import Foundation

// VaultKey app icon.
//
// A dark navy squircle, a machined vault ring, and a single keyhole. Drawn
// directly at every icon size so the ring and keyhole stay crisp at 16 px.

let canvas: CGFloat = 1024
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.iconset", isDirectory: true)

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha).cgColor
}

func drawDesign(in context: CGContext) {
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    // MARK: Squircle

    let squircleRect = CGRect(x: 56, y: 56, width: 912, height: 912)
    let squircle = CGPath(
        roundedRect: squircleRect,
        cornerWidth: 208,
        cornerHeight: 208,
        transform: nil
    )

    context.saveGState()
    context.addPath(squircle)
    context.clip()

    // Deep navy base.
    let base = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color(0.035, 0.055, 0.145),
            color(0.055, 0.090, 0.245),
            color(0.075, 0.125, 0.330),
        ] as CFArray,
        locations: [0, 0.52, 1]
    )!
    context.drawLinearGradient(
        base,
        start: CGPoint(x: 180, y: 950),
        end: CGPoint(x: 860, y: 70),
        options: []
    )

    // Cool light from the upper left.
    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color(0.42, 0.56, 1.0, 0.34),
            color(0.28, 0.40, 0.95, 0.10),
            color(0.10, 0.16, 0.40, 0.0),
        ] as CFArray,
        locations: [0, 0.45, 1]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 360, y: 790),
        startRadius: 0,
        endCenter: CGPoint(x: 360, y: 790),
        endRadius: 620,
        options: []
    )

    // Soft vignette at the bottom right.
    let vignette = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color(0.0, 0.0, 0.0, 0.0),
            color(0.0, 0.0, 0.0, 0.26),
        ] as CFArray,
        locations: [0.45, 1]
    )!
    context.drawRadialGradient(
        vignette,
        startCenter: CGPoint(x: 620, y: 460),
        startRadius: 80,
        endCenter: CGPoint(x: 620, y: 460),
        endRadius: 720,
        options: []
    )

    context.restoreGState()

    // Inner rim light.
    context.saveGState()
    context.addPath(squircle)
    context.setStrokeColor(color(1, 1, 1, 0.14))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    // MARK: Vault ring

    let center = CGPoint(x: 512, y: 512)
    let ringRadius: CGFloat = 278

    // Recessed disc behind the ring.
    let disc = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color(0.55, 0.66, 1.0, 0.12),
            color(0.30, 0.40, 0.85, 0.05),
            color(0.02, 0.04, 0.12, 0.12),
        ] as CFArray,
        locations: [0, 0.62, 1]
    )!
    context.saveGState()
    context.addEllipse(in: CGRect(
        x: center.x - ringRadius,
        y: center.y - ringRadius,
        width: ringRadius * 2,
        height: ringRadius * 2
    ))
    context.clip()
    context.drawRadialGradient(
        disc,
        startCenter: CGPoint(x: center.x - 90, y: center.y + 120),
        startRadius: 0,
        endCenter: center,
        endRadius: ringRadius,
        options: []
    )
    context.restoreGState()

    // Wide, faint halo.
    context.saveGState()
    context.setStrokeColor(color(0.48, 0.62, 1.0, 0.16))
    context.setLineWidth(34)
    context.strokeEllipse(in: CGRect(
        x: center.x - ringRadius,
        y: center.y - ringRadius,
        width: ringRadius * 2,
        height: ringRadius * 2
    ))
    context.restoreGState()

    // Main ring.
    context.saveGState()
    context.setStrokeColor(color(0.91, 0.95, 1.0, 0.95))
    context.setLineWidth(17)
    context.strokeEllipse(in: CGRect(
        x: center.x - ringRadius,
        y: center.y - ringRadius,
        width: ringRadius * 2,
        height: ringRadius * 2
    ))
    context.restoreGState()

    // Inner machined ring.
    context.saveGState()
    context.setStrokeColor(color(0.68, 0.78, 1.0, 0.22))
    context.setLineWidth(4)
    let innerRadius = ringRadius - 27
    context.strokeEllipse(in: CGRect(
        x: center.x - innerRadius,
        y: center.y - innerRadius,
        width: innerRadius * 2,
        height: innerRadius * 2
    ))
    context.restoreGState()

    // Tick marks around the ring.
    let tickCount = 48
    for index in 0..<tickCount {
        let angle = (CGFloat(index) / CGFloat(tickCount)) * .pi * 2 - .pi / 2
        let isMajor = index % 4 == 0
        let inner = ringRadius + (isMajor ? 24 : 27)
        let outer = ringRadius + (isMajor ? 46 : 35)
        let start = CGPoint(
            x: center.x + cos(angle) * inner,
            y: center.y + sin(angle) * inner
        )
        let end = CGPoint(
            x: center.x + cos(angle) * outer,
            y: center.y + sin(angle) * outer
        )
        context.setStrokeColor(color(0.82, 0.89, 1.0, isMajor ? 0.78 : 0.34))
        context.setLineWidth(isMajor ? 6 : 3)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    // MARK: Keyhole

    // Keyhole glow.
    context.saveGState()
    let keyGlow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color(0.55, 0.72, 1.0, 0.38),
            color(0.45, 0.62, 1.0, 0.0),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        keyGlow,
        startCenter: CGPoint(x: 512, y: 520),
        startRadius: 0,
        endCenter: CGPoint(x: 512, y: 520),
        endRadius: 190,
        options: []
    )
    context.restoreGState()

    let keyhole = CGMutablePath()
    keyhole.addEllipse(in: CGRect(x: 456, y: 502, width: 112, height: 112))
    keyhole.addRoundedRect(
        in: CGRect(x: 472, y: 396, width: 80, height: 140),
        cornerWidth: 28,
        cornerHeight: 28
    )

    context.saveGState()
    context.addPath(keyhole)
    context.setFillColor(color(0.96, 0.98, 1.0, 0.98))
    context.fillPath()
    context.restoreGState()

    // A hairline of blue on the keyhole's lower edge for depth.
    context.saveGState()
    context.setStrokeColor(color(0.38, 0.54, 1.0, 0.35))
    context.setLineWidth(2)
    context.move(to: CGPoint(x: 490, y: 405))
    context.addLine(to: CGPoint(x: 534, y: 405))
    context.strokePath()
    context.restoreGState()
}

func render(pixels: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "VaultKeyIcon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Couldn't create bitmap",
        ])
    }
    rep.size = NSSize(width: pixels, height: pixels)

    guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "VaultKeyIcon", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Couldn't create graphics context",
        ])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawDesign(in: context)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "VaultKeyIcon", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Couldn't encode PNG",
        ])
    }
    try data.write(to: url, options: .atomic)
}

struct Variant {
    let name: String
    let pixels: Int
}

let variants: [Variant] = [
    Variant(name: "icon_16x16.png", pixels: 16),
    Variant(name: "icon_16x16@2x.png", pixels: 32),
    Variant(name: "icon_32x32.png", pixels: 32),
    Variant(name: "icon_32x32@2x.png", pixels: 64),
    Variant(name: "icon_128x128.png", pixels: 128),
    Variant(name: "icon_128x128@2x.png", pixels: 256),
    Variant(name: "icon_256x256.png", pixels: 256),
    Variant(name: "icon_256x256@2x.png", pixels: 512),
    Variant(name: "icon_512x512.png", pixels: 512),
    Variant(name: "icon_512x512@2x.png", pixels: 1024),
]

for variant in variants {
    try render(
        pixels: variant.pixels,
        to: outputDirectory.appendingPathComponent(variant.name)
    )
}

// A standalone 1024 px preview for README and inspection.
try render(pixels: 1024, to: outputDirectory.deletingLastPathComponent().appendingPathComponent("AppIcon-1024.png"))

print("Wrote \(variants.count) icon variants to \(outputDirectory.path)")
