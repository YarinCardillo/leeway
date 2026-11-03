#!/usr/bin/env swift
import AppKit
import CoreText

/// Generates portable icon artwork. CoreText is needed only when regenerating the SVG.
struct WordmarkIconGenerator {
    private let canvas: CGFloat = 1024
    private let wordmarkWidth: CGFloat = 800

    func write(to directory: URL) throws {
        let assets = directory.appendingPathComponent("Assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let paths = try centeredPaths()
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" fill="#ffffff">
        \(paths.map { "<path d=\"\(svgCommands($0))\"/>" }.joined(separator: "\n"))
        </svg>
        """
        try (svg + "\n").write(to: assets.appendingPathComponent("wordmark.svg"), atomically: true, encoding: .utf8)
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        try (data + Data([10])).write(to: directory.appendingPathComponent("icon.json"), options: .atomic)
    }

    private func centeredPaths() throws -> [CGPath] {
        let paths = try glyphPaths()
        let bounds = paths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
        let scale = wordmarkWidth / bounds.width
        var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
            tx: (canvas - bounds.width * scale) / 2 - bounds.minX * scale,
            ty: (canvas + bounds.height * scale) / 2 + bounds.minY * scale)
        return paths.map { $0.copy(using: &transform)! }
    }

    private func glyphPaths() throws -> [CGPath] {
        let text = NSAttributedString(string: "Leeway", attributes: [.font: NSFont.systemFont(ofSize: 200, weight: .semibold)])
        let line = CTLineCreateWithAttributedString(text)
        var paths: [CGPath] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                var translation = CGAffineTransform(translationX: position.x, y: position.y)
                guard let path = CTFontCreatePathForGlyph(font, glyph, &translation) else { throw GenerationError.missingOutline }
                paths.append(path)
            }
        }
        return paths
    }

    private var document: [String: Any] {
        [
            "fill": [
                "linear-gradient": ["srgb:0.37255,0.49020,0.41961,1.00000", "srgb:0.24706,0.35294,0.29020,1.00000"],
                "orientation": ["start": ["x": 0.5, "y": 0], "stop": ["x": 0.5, "y": 1]]
            ],
            "groups": [[
                "layers": [["blend-mode": "normal", "fill": "none", "glass": false, "hidden": false,
                            "image-name": "wordmark.svg", "name": "Leeway", "opacity": 1,
                            "position": ["scale": 1, "translation-in-points": [0, 0]]]],
                "shadow": ["kind": "neutral", "opacity": 0.5],
                "translucency": ["enabled": false, "value": 0.5]
            ]],
            "supported-platforms": ["squares": "shared"]
        ]
    }

    private func svgCommands(_ path: CGPath) -> String {
        var commands: [String] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            func point(_ index: Int) -> String {
                let p = element.points[index]
                return String(format: "%.3f %.3f", locale: Locale(identifier: "en_US_POSIX"), p.x, p.y)
            }
            switch element.type {
            case .moveToPoint: commands.append("M" + point(0))
            case .addLineToPoint: commands.append("L" + point(0))
            case .addQuadCurveToPoint: commands.append("Q" + point(0) + " " + point(1))
            case .addCurveToPoint: commands.append("C" + point(0) + " " + point(1) + " " + point(2))
            case .closeSubpath: commands.append("Z")
            @unknown default: preconditionFailure("Unsupported path element")
            }
        }
        return commands.joined(separator: " ")
    }

    private enum GenerationError: Error { case missingOutline }
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count <= 1 else { fatalError("Usage: swift scripts/generate_app_icon.swift [output.icon]") }
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = arguments.first.map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("App/Resources/AppIcon.icon")
try WordmarkIconGenerator().write(to: output)
print("Generated \(output.lastPathComponent): outlined SF Pro Semibold wordmark on sage gradient")
