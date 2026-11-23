import Foundation

/// A reading shared by the visual cursor, keyboard navigation and VoiceOver.
public struct ChartReadout: Equatable, Sendable {
    public let date: Date
    public let lower: Double
    public let upper: Double
    public let isForecast: Bool
}

extension AccountUsage {
    /// Ten percentage points above all plotted values leave space around the limit and labels.
    public var chartYDomain: ClosedRange<Double> {
        0...(max(100, upperForecast ?? 0, weeklyUsed ?? 0, history.map(\.used).max() ?? 0) + 10)
    }

    /// Selects a measured sample, or the held reading of an activity-based account, or interpolates both
    /// forecast bounds at the requested time.
    public func chartReadout(at date: Date) -> ChartReadout? {
        guard let reset else { return nil }
        let series = chartSeries(from: reset.addingTimeInterval(-7 * 86400), to: reset)
        guard let anchor = series.now else { return nil }
        if date > anchor.date, reset > anchor.date, let low = lowerForecast, let high = upperForecast {
            // Forecast points are shown per hour: the projection is a pace, not minute-level data.
            let hour = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 3600).rounded() * 3600)
            let date = min(max(hour, anchor.date), reset)
            let fraction = date.timeIntervalSince(anchor.date) / reset.timeIntervalSince(anchor.date)
            return ChartReadout(date: date, lower: anchor.used + (max(anchor.used, low) - anchor.used) * fraction,
                upper: anchor.used + (max(anchor.used, high) - anchor.used) * fraction, isForecast: true)
        }
        if isActivityBased { return heldReadout(at: date, line: series.line) }
        guard let point = series.line.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) else { return nil }
        return ChartReadout(date: point.date, lower: point.used, upper: point.used, isForecast: false)
    }

    /// Readings that arrive only with activity hold their value until the next one, so the cursor reads the last
    /// reading at or before its own time and moves continuously instead of jumping between readings.
    private func heldReadout(at date: Date, line: [UsagePoint]) -> ChartReadout? {
        guard let first = line.first else { return nil }
        guard let held = line.last(where: { $0.date <= date }) else {
            return ChartReadout(date: first.date, lower: first.used, upper: first.used, isForecast: false)
        }
        return ChartReadout(date: date, lower: held.used, upper: held.used, isForecast: false)
    }

    /// Keyboard and accessibility stepping visit measured samples and daily forecast positions.
    public var chartInspectionPoints: [ChartReadout] {
        guard let reset else { return [] }
        let series = chartSeries(from: reset.addingTimeInterval(-7 * 86400), to: reset)
        var dates = series.line.map(\.date)
        if let anchor = series.now, anchor.date < reset, upperForecast != nil {
            var date = anchor.date.addingTimeInterval(86400)
            while date < reset { dates.append(date); date = date.addingTimeInterval(86400) }
            dates.append(reset)
        }
        return dates.compactMap { chartReadout(at: $0) }
    }
}
