import AppModel
import SwiftUI

/// Fixed-scale usage and forecast segments with target ticks drawn above both fills.
struct ForecastMeter: View {
    /// Semantic colours remain unchanged on the neutral account selection.
    struct Palette {
        let track: Color
        let used: Color
        let forecast: Color
        let tick: Color
        let tickOutline: Color

        static func standard(verdict: Color) -> Palette {
            Palette(track: Color(nsColor: .secondarySystemFill),
                    used: .primary, forecast: verdict, tick: .primary, tickOutline: Color(nsColor: .textBackgroundColor))
        }
    }

    let layout: ForecastMeterLayout
    let palette: Palette
    var barHeight: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let ticks = layout.targetTickPositions(width: width)
            ZStack(alignment: .leading) {
                palette.track.clipShape(Capsule())
                Capsule().fill(palette.used).frame(width: width * layout.usedFraction)
                if let forecast = layout.forecastFractions {
                    segment(forecast, width: width).fill(palette.forecast)
                }
            }
            .frame(height: barHeight)
            .overlay(alignment: .leading) {
                targetTick(at: ticks.lowerBound)
                targetTick(at: ticks.upperBound)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func targetTick(at position: Double) -> some View {
        Rectangle().fill(palette.tickOutline)
            .frame(width: ForecastMeterLayout.targetTickOutlineWidth, height: barHeight + 4)
            .overlay(Rectangle().fill(palette.tick).frame(width: 1))
            .offset(x: position - ForecastMeterLayout.targetTickOutlineWidth / 2)
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
