import AppKit
import AppModel
import SwiftUI

/// Menu rows keep AppKit's selection, so the meter is an inline attachment redrawn per appearance.
@MainActor
enum NativeUsageMeter {
    static let height: CGFloat = 10
    private static let renderScale: CGFloat = 3

    static func attachment(account: AccountUsage, width: CGFloat) -> NSAttributedString? {
        guard let layout = ForecastMeterLayout(account: account) else { return nil }
        let tint = Color(nsColor: RiskTextColor.verdict(account))
        let palette = ForecastMeter.Palette.standard(verdict: tint)
        let renders = [ColorScheme.light, .dark].map { render(layout, palette: palette, scheme: $0, width: width) }
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            guard let render = renders[isDark ? 1 : 0], let context = NSGraphicsContext.current?.cgContext else { return false }
            context.draw(render, in: rect)
            return true
        }
        let attachment = NSTextAttachment()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        return NSAttributedString(attachment: attachment)
    }

    private static func render(_ layout: ForecastMeterLayout, palette: ForecastMeter.Palette, scheme: ColorScheme, width: CGFloat) -> CGImage? {
        let meter = ForecastMeter(layout: layout, palette: palette)
            .frame(width: width, height: height)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: meter)
        renderer.scale = renderScale
        return renderer.cgImage
    }
}
