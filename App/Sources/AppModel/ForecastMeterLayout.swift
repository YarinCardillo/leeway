import Foundation

/// Where each mark of the forecast meter sits, as fractions of the meter's width.
///
/// The scale runs from 0 to 100% and stretches in steps of ten when the forecast (or the usage) goes past
/// the limit, so a crossing is visible as a mark beyond a hairline instead of a clipped bar.
public struct ForecastMeterLayout: Equatable, Sendable {
    private static let limit = 100.0
    private static let domainStep = 10.0

    public let domainMaximum: Double
    public let usedFraction: Double
    public let forecastFractions: ClosedRange<Double>?
    public let targetFractions: ClosedRange<Double>

    /// Nil when the account has no reading to draw.
    public init?(account: AccountUsage) {
        guard let used = account.weeklyUsed else { return nil }
        let highest = max(used, account.upperForecast ?? 0, Self.limit)
        domainMaximum = (highest / Self.domainStep).rounded(.up) * Self.domainStep
        usedFraction = min(1, used / domainMaximum)
        forecastFractions = Self.range(account.lowerForecast, account.upperForecast, in: domainMaximum)
        targetFractions = Self.range(account.targetLow, account.targetHigh, in: domainMaximum) ?? 0...0
    }

    /// The limit's position, only when it is not the end of the scale.
    public var limitFraction: Double? {
        domainMaximum > Self.limit ? Self.limit / domainMaximum : nil
    }

    private static func range(_ low: Double?, _ high: Double?, in domain: Double) -> ClosedRange<Double>? {
        guard let low, let high, low <= high else { return nil }
        return min(1, low / domain)...min(1, high / domain)
    }
}
