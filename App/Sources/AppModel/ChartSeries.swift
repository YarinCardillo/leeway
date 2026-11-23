import Foundation

/// What the weekly chart draws: the measured line and the "now" point, which is always the line's last point.
public struct ChartSeries: Equatable, Sendable {
    public let line: [UsagePoint]
    public let now: UsagePoint?

    /// A measured segment needs at least two distinct timestamps. A lone sample is only the now dot.
    public var measuredLine: [UsagePoint] { line.count > 1 ? line : [] }

    /// The estimated start of the measured line, ending on the first real point so the two parts join.
    public var estimatedLine: [UsagePoint] {
        guard let firstReal = measuredLine.firstIndex(where: { !$0.isEstimated }) else { return measuredLine }
        return firstReal == 0 ? [] : Array(measuredLine[...firstReal])
    }

    /// The measured line from the first real reading on.
    public var realLine: [UsagePoint] {
        guard let firstReal = measuredLine.firstIndex(where: { !$0.isEstimated }) else { return [] }
        return Array(measuredLine[firstReal...])
    }
}

extension AccountUsage {
    /// The measured line inside `start...end`, ending exactly on the newest known point.
    ///
    /// The live reading and the stored history come from two sources; drawing them separately put the
    /// "now" dot off the line whenever one was newer. The newest of the two is the anchor for the line,
    /// the dot and the projections. Activity-based usage does not change without activity, so its last
    /// reading is held up to `now`, and the projections start there.
    public func chartSeries(from start: Date, to end: Date, now: Date = Date()) -> ChartSeries {
        let measured = measuredSeries(from: start, to: end)
        guard isActivityBased, let last = measured.line.last, now > last.date, now <= end else { return measured }
        let held = UsagePoint(date: now, used: last.used, isEstimated: last.isEstimated)
        return ChartSeries(line: measured.line + [held], now: held)
    }

    private func measuredSeries(from start: Date, to end: Date) -> ChartSeries {
        let sorted = history.filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
        var inWeek: [UsagePoint] = []
        for point in sorted {
            if inWeek.last?.date == point.date { inWeek.removeLast() }
            inWeek.append(point)
        }
        guard let reading = currentReading, reading.date >= start, reading.date <= end,
              reading.date >= (inWeek.last?.date ?? .distantPast) else {
            return ChartSeries(line: inWeek, now: inWeek.last)
        }
        let line = inWeek.filter { $0.date < reading.date } + [reading]
        return ChartSeries(line: line, now: reading)
    }

    private var currentReading: UsagePoint? {
        guard let recordedAt, let weeklyUsed else { return nil }
        return UsagePoint(date: recordedAt, used: weeklyUsed)
    }
}
