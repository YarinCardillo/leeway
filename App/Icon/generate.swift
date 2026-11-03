#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Generate from the repository root: swift App/Icon/generate.swift
// The 1024 canvas uses the macOS icon grid's 100-point inset and 824-point ground.
// The existing Phosphor target glyph is covered by Resources/THIRD_PARTY_NOTICES.
let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = app.appendingPathComponent("Sources/LeewayApp/Resources/StatusIcons.xcassets")
let destination = assets.appendingPathComponent("AppIcon.appiconset")
let glyphURL = assets.appendingPathComponent("target-bold.imageset/target-bold.svg")
let svg = try String(contentsOf: glyphURL, encoding: .utf8).replacingOccurrences(of: "currentColor", with: "#ffffff")
guard let glyph = NSImage(data: Data(svg.utf8)) else { fatalError("Cannot load the target glyph") }

func drawGround(_ context: CGContext) {
    let bounds = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: bounds, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: CGColor(gray: 0, alpha: 0.28))
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 0.17, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let colors = [CGColor(gray: 0.13, alpha: 1), CGColor(gray: 0.24, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    context.restoreGState()
    context.addPath(shape)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
    context.setLineWidth(2)
    context.strokePath()
}

func render(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.setShouldAntialias(true)
    drawGround(context)
    context.setShadow(offset: CGSize(width: 0, height: -3), blur: 4, color: CGColor(gray: 0, alpha: 0.25))
    glyph.draw(in: CGRect(x: 224, y: 224, width: 576, height: 576),
               from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(size)x\(size)@\(scale)x.png"
        try render(pixels: size * scale).write(to: destination.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let manifest: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try data.write(to: destination.appendingPathComponent("Contents.json"))
