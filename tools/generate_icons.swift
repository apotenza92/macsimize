#!/usr/bin/env swift

import AppKit

struct IconSpec {
    let size: Int
    let logicalSize: String
    let scale: String
    let filename: String
}

struct IconTheme {
    let baseTop: NSColor
    let baseBottom: NSColor
    let glow: NSColor
    let sheenTop: NSColor
    let sheenBottom: NSColor
    let vignette: NSColor
    let glyphTopAlpha: CGFloat
    let glyphBottomAlpha: CGFloat
    let glyphShadow: NSColor
}

struct IconSet {
    let folderName: String
    let label: String
    let theme: IconTheme
}

let specs: [IconSpec] = [
    .init(size: 16, logicalSize: "16x16", scale: "1x", filename: "icon_16x16.png"),
    .init(size: 32, logicalSize: "16x16", scale: "2x", filename: "icon_16x16@2x.png"),
    .init(size: 32, logicalSize: "32x32", scale: "1x", filename: "icon_32x32.png"),
    .init(size: 64, logicalSize: "32x32", scale: "2x", filename: "icon_32x32@2x.png"),
    .init(size: 128, logicalSize: "128x128", scale: "1x", filename: "icon_128x128.png"),
    .init(size: 256, logicalSize: "128x128", scale: "2x", filename: "icon_128x128@2x.png"),
    .init(size: 256, logicalSize: "256x256", scale: "1x", filename: "icon_256x256.png"),
    .init(size: 512, logicalSize: "256x256", scale: "2x", filename: "icon_256x256@2x.png"),
    .init(size: 512, logicalSize: "512x512", scale: "1x", filename: "icon_512x512.png"),
    .init(size: 1024, logicalSize: "512x512", scale: "2x", filename: "icon_512x512@2x.png")
]

let stableTheme = IconTheme(
    baseTop: NSColor(calibratedRed: 0.29, green: 0.86, blue: 0.38, alpha: 1.0),
    baseBottom: NSColor(calibratedRed: 0.17, green: 0.73, blue: 0.27, alpha: 1.0),
    glow: NSColor(calibratedRed: 0.84, green: 1.00, blue: 0.86, alpha: 0.34),
    sheenTop: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.16),
    sheenBottom: NSColor(calibratedRed: 0.86, green: 1.00, blue: 0.87, alpha: 0.00),
    vignette: NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.09, alpha: 0.16),
    glyphTopAlpha: 0.98,
    glyphBottomAlpha: 0.82,
    glyphShadow: NSColor(calibratedWhite: 0.0, alpha: 0.14)
)

let betaTheme = IconTheme(
    baseTop: NSColor(calibratedRed: 0.52, green: 0.79, blue: 1.00, alpha: 1.0),
    baseBottom: NSColor(calibratedRed: 0.33, green: 0.19, blue: 0.82, alpha: 1.0),
    glow: NSColor(calibratedRed: 0.87, green: 0.92, blue: 1.00, alpha: 0.58),
    sheenTop: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.22),
    sheenBottom: NSColor(calibratedRed: 0.88, green: 0.91, blue: 1.00, alpha: 0.00),
    vignette: NSColor(calibratedRed: 0.08, green: 0.07, blue: 0.24, alpha: 0.28),
    glyphTopAlpha: 0.98,
    glyphBottomAlpha: 0.78,
    glyphShadow: NSColor(calibratedWhite: 0.0, alpha: 0.16)
)

let iconSets: [IconSet] = [
    .init(folderName: "AppIcon.appiconset", label: "stable", theme: stableTheme),
    .init(folderName: "AppIconBeta.appiconset", label: "beta", theme: betaTheme)
]

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let assetsCatalog = cwd.appendingPathComponent("Macsimize/Assets.xcassets", isDirectory: true)
let accentColors = assetsCatalog.appendingPathComponent("AccentColor.colorset", isDirectory: true)

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func configuredStrokePath(lineWidth: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    return path
}

func drawCirclePlusGlyph(in rect: NSRect, strokeColor: NSColor, lineWidth: CGFloat) {
    NSGraphicsContext.saveGraphicsState()

    let transform = NSAffineTransform()
    transform.translateX(by: rect.minX, yBy: rect.minY)
    transform.scaleX(by: rect.width / 24.0, yBy: rect.height / 24.0)
    transform.concat()

    strokeColor.setStroke()

    let outlineWidth = lineWidth * 0.92

    let circle = NSBezierPath(ovalIn: NSRect(x: 2.4, y: 2.4, width: 19.2, height: 19.2))
    circle.lineWidth = outlineWidth
    circle.lineJoinStyle = .round
    circle.lineCapStyle = .round
    circle.stroke()

    let horizontal = configuredStrokePath(lineWidth: lineWidth)
    horizontal.move(to: NSPoint(x: 7.0, y: 12.0))
    horizontal.line(to: NSPoint(x: 17.0, y: 12.0))
    horizontal.stroke()

    let vertical = configuredStrokePath(lineWidth: lineWidth)
    vertical.move(to: NSPoint(x: 12.0, y: 7.0))
    vertical.line(to: NSPoint(x: 12.0, y: 17.0))
    vertical.stroke()

    NSGraphicsContext.restoreGraphicsState()
}

func drawGlyphVerticalGradient(in rect: NSRect, lineWidth: CGFloat, topAlpha: CGFloat, bottomAlpha: CGFloat, shadowColor: NSColor) {
    let maskImage = NSImage(size: rect.size)
    maskImage.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: rect.size).fill()
    drawCirclePlusGlyph(in: NSRect(origin: .zero, size: rect.size), strokeColor: .white, lineWidth: lineWidth)
    maskImage.unlockFocus()

    guard let maskCG = maskImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let ctx = NSGraphicsContext.current?.cgContext,
          let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedWhite: 1.0, alpha: topAlpha).cgColor,
                NSColor(calibratedWhite: 1.0, alpha: bottomAlpha).cgColor
            ] as CFArray,
            locations: [0.0, 1.0]
          ) else {
        drawCirclePlusGlyph(in: rect, strokeColor: NSColor(calibratedWhite: 1.0, alpha: bottomAlpha), lineWidth: lineWidth)
        return
    }

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -rect.height * 0.01), blur: rect.width * 0.04, color: shadowColor.cgColor)
    ctx.clip(to: rect, mask: maskCG)
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )
    ctx.restoreGState()
}

func drawIcon(size: Int, theme: IconTheme) -> NSBitmapImageRep {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to allocate bitmap for icon size \(size)")
    }

    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: s, height: s)
    NSColor.clear.setFill()
    canvas.fill()

    let outerInset = s * 0.06
    let outerRect = canvas.insetBy(dx: outerInset, dy: outerInset)
    let outerPath = roundedRect(outerRect, radius: s * 0.24)

    let baseGradient = NSGradient(colors: [theme.baseTop, theme.baseBottom])!
    baseGradient.draw(in: outerPath, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    outerPath.addClip()

    let glowGradient = NSGradient(colors: [theme.glow, NSColor.clear])!
    glowGradient.draw(in: outerRect, relativeCenterPosition: NSPoint(x: -0.22, y: 0.30))

    let sheenGradient = NSGradient(colors: [theme.sheenTop, theme.sheenBottom])!
    sheenGradient.draw(in: outerRect, angle: -35)

    let vignetteGradient = NSGradient(colors: [NSColor.clear, theme.vignette])!
    vignetteGradient.draw(in: outerRect, relativeCenterPosition: NSPoint(x: 0.0, y: -0.20))

    NSGraphicsContext.restoreGraphicsState()

    let outerStroke = roundedRect(outerRect.insetBy(dx: s * 0.004, dy: s * 0.004), radius: s * 0.23)
    NSColor(calibratedWhite: 1.0, alpha: 0.16).setStroke()
    outerStroke.lineWidth = max(1.0, s * 0.01)
    outerStroke.stroke()

    drawGlyphVerticalGradient(
        in: outerRect,
        lineWidth: 1.85,
        topAlpha: theme.glyphTopAlpha,
        bottomAlpha: theme.glyphBottomAlpha,
        shadowColor: theme.glyphShadow
    )

    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MacsimizeIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try data.write(to: url, options: .atomic)
}

func appIconContentsJSON() -> String {
    let imageEntries = specs.map { spec in
        "    { \"filename\" : \"\(spec.filename)\", \"idiom\" : \"mac\", \"scale\" : \"\(spec.scale)\", \"size\" : \"\(spec.logicalSize)\" }"
    }
    return "{\n  \"images\" : [\n\(imageEntries.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
}

func writeCatalogScaffolding() throws {
    try fm.createDirectory(at: assetsCatalog, withIntermediateDirectories: true)
    try fm.createDirectory(at: accentColors, withIntermediateDirectories: true)

    try "{\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n"
        .data(using: .utf8)?
        .write(to: assetsCatalog.appendingPathComponent("Contents.json"), options: .atomic)

    let accentJSON = """
    {
      "colors" : [
        {
          "color" : {
            "color-space" : "srgb",
            "components" : {
              "alpha" : "1.000",
              "blue" : "0.270",
              "green" : "0.730",
              "red" : "0.170"
            }
          },
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try accentJSON.data(using: .utf8)?.write(to: accentColors.appendingPathComponent("Contents.json"), options: .atomic)
}

try writeCatalogScaffolding()

for iconSet in iconSets {
    let iconsetURL = assetsCatalog.appendingPathComponent(iconSet.folderName, isDirectory: true)
    try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    for spec in specs {
        let image = drawIcon(size: spec.size, theme: iconSet.theme)
        let out = iconsetURL.appendingPathComponent(spec.filename)
        try writePNG(image, to: out)
        print("Wrote \(out.path)")
    }

    let contentsURL = iconsetURL.appendingPathComponent("Contents.json")
    try appIconContentsJSON().data(using: .utf8)?.write(to: contentsURL, options: .atomic)
    print("Updated \(contentsURL.path) [\(iconSet.label)]")
}
