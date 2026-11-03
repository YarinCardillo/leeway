import Foundation

public struct HistoryPoint: Codable, Equatable, Sendable {
    public let at: Date
    public let pct: Double

    public init(at: Date, pct: Double) { self.at = at; self.pct = pct }

    public init(from decoder: any Decoder) throws {
        var values = try decoder.unkeyedContainer()
        at = try values.decode(Date.self)
        pct = try values.decode(Double.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(at)
        try values.encode(pct)
    }
}

public enum Confidence: String, Codable, Sendable { case none, low, medium, high }

public struct Forecast: Codable, Equatable, Sendable {
    public let sevenDayPctAtReset: Double?
    public let averagePctAtReset: Double?
    public let recentPctAtReset: Double?
    public let rangeLow: Double?
    public let rangeHigh: Double?
    public let nextRoundPct: Double?
    public let exhaustsAt: Date?
    public let confidence: Confidence

    public init(averagePctAtReset: Double?, recentPctAtReset: Double?,
                rangeLow: Double?, rangeHigh: Double?, nextRoundPct: Double?, exhaustsAt: Date?, confidence: Confidence) {
        self.sevenDayPctAtReset = recentPctAtReset
        self.averagePctAtReset = averagePctAtReset; self.recentPctAtReset = recentPctAtReset
        self.rangeLow = rangeLow; self.rangeHigh = rangeHigh; self.nextRoundPct = nextRoundPct
        self.exhaustsAt = exhaustsAt; self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case sevenDayPctAtReset, averagePctAtReset, recentPctAtReset, rangeLow, rangeHigh
        case nextRoundPct, exhaustsAt, confidence
    }

    /// Keeps unknown forecast values as explicit nulls in API responses.
    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(sevenDayPctAtReset, forKey: .sevenDayPctAtReset)
        try fields.encode(averagePctAtReset, forKey: .averagePctAtReset)
        try fields.encode(recentPctAtReset, forKey: .recentPctAtReset)
        try fields.encode(rangeLow, forKey: .rangeLow)
        try fields.encode(rangeHigh, forKey: .rangeHigh)
        try fields.encode(nextRoundPct, forKey: .nextRoundPct)
        try fields.encode(exhaustsAt, forKey: .exhaustsAt)
        try fields.encode(confidence, forKey: .confidence)
    }

    public static let empty = Forecast(averagePctAtReset: nil,
        recentPctAtReset: nil, rangeLow: nil, rangeHigh: nil, nextRoundPct: nil,
        exhaustsAt: nil, confidence: .none)
}

public enum Forecaster {
    private static let hour: TimeInterval = 3600
    private static let minimumRecentSpan = 6 * hour
    static let week: TimeInterval = 7 * 24 * hour

    /// Projects current-window history. Missing or expired windows return an empty forecast.
    public static func forecast(_ history: [HistoryPoint], resetsAt: Date?, now: Date) -> Forecast {
        guard let reset = resetsAt, reset > now else { return .empty }
        let points = history.filter { $0.at <= now && $0.at >= reset.addingTimeInterval(-week) }
            .sorted { $0.at < $1.at }
        guard let latest = points.last else { return .empty }
        let recent = points.filter { $0.at >= now.addingTimeInterval(-24 * hour) }
        let slope = recentPace(recent)
        let remaining = reset.timeIntervalSince(now)
        let elapsed = min(max(now.timeIntervalSince(reset.addingTimeInterval(-week)) / week, 0), 1)
        let average = points.count >= 2 && elapsed > 0 ? rounded(max(latest.pct, latest.pct / elapsed)) : nil
        let recentEnd = slope.map { rounded(max(latest.pct, latest.pct + $0 * remaining)) }
        let range = [average, recentEnd].compactMap { $0 }
        let exhausts = (recentEnd ?? 0) > 100 && (slope ?? 0) > 0
            ? now.addingTimeInterval(max(100 - latest.pct, 0) / slope!) : nil
        let roundValues = points.filter { $0.at >= now.addingTimeInterval(-5 * hour) }.map(\.pct)
        let roundCost = max(latest.pct - (roundValues.min() ?? latest.pct), 1)
        return Forecast(averagePctAtReset: average, recentPctAtReset: recentEnd,
            rangeLow: range.min(), rangeHigh: range.max(),
            nextRoundPct: rounded(latest.pct + roundCost), exhaustsAt: exhausts,
            confidence: confidence(recent, hasTrend: slope != nil && now.timeIntervalSince(latest.at) <= 6 * hour))
    }

    private static func recentPace(_ points: [HistoryPoint]) -> Double? {
        guard points.count >= 2, let first = points.first, let last = points.last,
              last.at.timeIntervalSince(first.at) >= minimumRecentSpan else { return nil }
        return max(last.pct - first.pct, 0) / last.at.timeIntervalSince(first.at)
    }

    private static func confidence(_ points: [HistoryPoint], hasTrend: Bool) -> Confidence {
        guard hasTrend else { return .low }
        if points.count >= 6, let first = points.first, let last = points.last,
           last.at.timeIntervalSince(first.at) >= 6 * hour { return .high }
        return points.count >= 2 ? .medium : .low
    }
}

func rounded(_ value: Double) -> Double { (value * 10).rounded(.toNearestOrEven) / 10 }
