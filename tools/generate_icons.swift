#!/usr/bin/env swift

import AppKit

struct IconSpec {
    let size: Int
    let filename: String
}

struct IconTheme {
    let baseTop: NSColor
    let baseBottom: NSColor
    let diagonalTop: NSColor
    let diagonalMid: NSColor
    let diagonalBottom: NSColor
    let vignetteBottom: NSColor
    let glyphTopAlpha: CGFloat
    let glyphBottomAlpha: CGFloat
}

struct IconSet {
    let folderName: String
    let label: String
    let theme: IconTheme
}

let specs: [IconSpec] = [
    .init(size: 16, filename: "icon_16x16.png"),
    .init(size: 32, filename: "icon_16x16@2x.png"),
    .init(size: 32, filename: "icon_32x32.png"),
    .init(size: 64, filename: "icon_32x32@2x.png"),
    .init(size: 128, filename: "icon_128x128.png"),
    .init(size: 256, filename: "icon_128x128@2x.png"),
    .init(size: 256, filename: "icon_256x256.png"),
    .init(size: 512, filename: "icon_256x256@2x.png"),
    .init(size: 512, filename: "icon_512x512.png"),
    .init(size: 1024, filename: "icon_512x512@2x.png")
]

let stableTheme = IconTheme(
    baseTop: NSColor(calibratedRed: 1.00, green: 0.90, blue: 0.47, alpha: 1.0),
    baseBottom: NSColor(calibratedRed: 0.95, green: 0.43, blue: 0.13, alpha: 1.0),
    diagonalTop: NSColor(calibratedRed: 1.00, green: 0.97, blue: 0.83, alpha: 0.38),
    diagonalMid: NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.31, alpha: 0.10),
    diagonalBottom: NSColor(calibratedRed: 0.82, green: 0.29, blue: 0.08, alpha: 0.22),
    vignetteBottom: NSColor(calibratedRed: 0.52, green: 0.17, blue: 0.04, alpha: 0.22),
    glyphTopAlpha: 0.98,
    glyphBottomAlpha: 0.74
)

let betaTheme = IconTheme(
    baseTop: NSColor(calibratedRed: 0.58, green: 0.79, blue: 1.00, alpha: 1.0),
    baseBottom: NSColor(calibratedRed: 0.27, green: 0.26, blue: 0.83, alpha: 1.0),
    diagonalTop: NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.00, alpha: 0.36),
    diagonalMid: NSColor(calibratedRed: 0.62, green: 0.73, blue: 1.00, alpha: 0.12),
    diagonalBottom: NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.57, alpha: 0.24),
    vignetteBottom: NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.32, alpha: 0.24),
    glyphTopAlpha: 0.98,
    glyphBottomAlpha: 0.74
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

func newStrokePath(lineWidth: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    return path
}

func drawMaximizeCornersGlyph(
    in rect: NSRect,
    strokeColor: NSColor,
    lineWidth: CGFloat
) {
    NSGraphicsContext.saveGraphicsState()

    let transform = NSAffineTransform()
    transform.translateX(by: rect.minX, yBy: rect.minY)
    transform.scaleX(by: rect.width / 24.0, yBy: rect.height / 24.0)
    transform.concat()

    strokeColor.setStroke()

    let topLeft = newStrokePath(lineWidth: lineWidth)
    topLeft.move(to: NSPoint(x: 9, y: 3.5))
    topLeft.line(to: NSPoint(x: 4.5, y: 3.5))
    topLeft.line(to: NSPoint(x: 4.5, y: 8))
    topLeft.stroke()

    let topRight = newStrokePath(lineWidth: lineWidth)
    topRight.move(to: NSPoint(x: 15, y: 3.5))
    topRight.line(to: NSPoint(x: 19.5, y: 3.5))
    topRight.line(to: NSPoint(x: 19.5, y: 8))
    topRight.stroke()

    let bottomLeft = newStrokePath(lineWidth: lineWidth)
    bottomLeft.move(to: NSPoint(x: 4.5, y: 16))
    bottomLeft.line(to: NSPoint(x: 4.5, y: 20.5))
    bottomLeft.line(to: NSPoint(x: 9, y: 20.5))
    bottomLeft.stroke()

    let bottomRight = newStrokePath(lineWidth: lineWidth)
    bottomRight.move(to: NSPoint(x: 15, y: 20.5))
    bottomRight.line(to: NSPoint(x: 19.5, y: 20.5))
    bottomRight.line(to: NSPoint(x: 19.5, y: 16))
    bottomRight.stroke()

    let center = newStrokePath(lineWidth: lineWidth * 0.92)
    center.move(to: NSPoint(x: 8.25, y: 12))
    center.line(to: NSPoint(x: 15.75, y: 12))
    center.stroke()

    NSGraphicsContext.restoreGraphicsState()
}

func drawGlyphVerticalGradient(
    in rect: NSRect,
    lineWidth: CGFloat,
    topAlpha: CGFloat,
    bottomAlpha: CGFloat
) {
    let maskImage = NSImage(size: rect.size)
    maskImage.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: rect.size).fill()
    drawMaximizeCornersGlyph(in: NSRect(origin: .zero, size: rect.size), strokeColor: .white, lineWidth: lineWidth)
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
        drawMaximizeCornersGlyph(in: rect, strokeColor: NSColor(calibratedWhite: 1.0, alpha: bottomAlpha), lineWidth: lineWidth)
        return
    }

    ctx.saveGState()
    ctx.clip(to: rect, mask: maskCG)
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )
    ctx.restoreGState()
}

func drawIcon(size: Int, theme: IconTheme) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))

    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: s, height: s)
    NSColor.clear.setFill()
    canvas.fill()

    let outerInset = s * 0.06
    let outerRect = canvas.insetBy(dx: outerInset, dy: outerInset)
    let outer = roundedRect(outerRect, radius: s * 0.24)

    let baseGradient = NSGradient(colors: [theme.baseTop, theme.baseBottom])!
    baseGradient.draw(in: outer, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    outer.addClip()

    let diagonal = NSGradient(colors: [theme.diagonalTop, theme.diagonalMid, theme.diagonalBottom])!
    diagonal.draw(in: outerRect, angle: -35)

    let subtleVignette = NSGradient(colors: [NSColor(calibratedWhite: 0.0, alpha: 0.0), theme.vignetteBottom])!
    subtleVignette.draw(in: outerRect, relativeCenterPosition: NSPoint(x: 0.0, y: -0.14))

    NSGraphicsContext.restoreGraphicsState()

    let innerGlowRect = outerRect.insetBy(dx: s * 0.085, dy: s * 0.085)
    let innerGlow = roundedRect(innerGlowRect, radius: s * 0.18)
    NSColor(calibratedWhite: 1.0, alpha: 0.09).setStroke()
    innerGlow.lineWidth = max(1.0, s * 0.012)
    innerGlow.stroke()

    var glyphRect = outerRect.insetBy(dx: s * 0.17, dy: s * 0.17)
    glyphRect.origin.y += s * 0.004

    drawGlyphVerticalGradient(
        in: glyphRect,
        lineWidth: max(1.7, s * 0.075),
        topAlpha: theme.glyphTopAlpha,
        bottomAlpha: theme.glyphBottomAlpha
    )

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MacsimizeIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try data.write(to: url, options: .atomic)
}

func appIconContentsJSON() -> String {
    """
    {
      "images" : [
        { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
        { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
        { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
        { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
        { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
        { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
        { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
        { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
        { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
        { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
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
              "blue" : "0.180",
              "green" : "0.490",
              "red" : "0.980"
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
