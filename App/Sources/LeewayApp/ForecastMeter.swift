import AppModel
import SwiftUI

/// Compact usage and forecast segments. The target is named in the caption and labelled in the detail chart.
struct ForecastMeter: View {
    /// Every colour the meter uses, so a highlighted menu row can use the system selection foreground.
    struct Palette {
        let track: Color
        let used: Color
        let forecast: Color
        let limit: Color

        static func standard(verdict: Color) -> Palette {
            Palette(track: Color(nsColor: .secondarySystemFill),
                    used: .primary, forecast: verdict, limit: Color(nsColor: .tertiaryLabelColor))
        }

        static var highlighted: Palette {
            let foreground = Color(nsColor: .selectedMenuItemTextColor)
            return Palette(track: foreground.opacity(0.22), used: foreground,
                           forecast: foreground.opacity(0.7), limit: foreground.opacity(0.6))
        }
    }

    let layout: ForecastMeterLayout
    let palette: Palette
    var barHeight: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                palette.track.clipShape(Capsule())
                segment(0...layout.usedFraction, width: width).fill(palette.used)
                if let forecast = layout.forecastFractions {
                    segment(forecast, width: width).fill(palette.forecast)
                }
                limitHairline(width: width)
            }
            .frame(height: barHeight).frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func limitHairline(width: CGFloat) -> some View {
        if let limit = layout.limitFraction {
            Rectangle().fill(palette.limit)
                .frame(width: 1, height: barHeight + 4)
                .offset(x: width * limit - 0.5)
        }
    }

    /// A capsule never narrower than its own height, so a point forecast is still a visible dot.
    private func segment(_ range: ClosedRange<Double>, width: CGFloat) -> some Shape {
        let start = width * range.lowerBound
        let length = max(barHeight, width * (range.upperBound - range.lowerBound))
        return OffsetCapsule(x: min(start, width - length), length: length)
    }
}

private struct OffsetCapsule: Shape {
    let x: CGFloat
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        Capsule().path(in: CGRect(x: rect.minX + x, y: rect.minY, width: length, height: rect.height))
    }
}
