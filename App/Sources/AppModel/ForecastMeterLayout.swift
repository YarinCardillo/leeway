import Foundation

/// Where each mark of the forecast meter sits, as fractions of the meter's width.
///
/// Every account uses the same 0 to 100% quota scale. Overflow is clipped in the meter only.
public struct ForecastMeterLayout: Equatable, Sendable {
    private static let limit = 100.0
    private static let minimumTickSeparation = 5.0
    public static let targetTickOutlineWidth = 3.0

    public let domainMaximum: Double
    public let usedFraction: Double
    public let forecastFractions: ClosedRange<Double>?
    public let targetFractions: ClosedRange<Double>

    /// Nil when the account has no reading to draw.
    public init?(account: AccountUsage) {
        guard let used = account.weeklyUsed else { return nil }
        domainMaximum = Self.limit
        usedFraction = max(0, min(1, used / domainMaximum))
        forecastFractions = Self.range(account.lowerForecast, account.upperForecast, in: domainMaximum)
        targetFractions = Self.range(account.targetLow, account.targetHigh, in: domainMaximum) ?? 0...0
    }

    /// Target tick centres in points, separated enough to distinguish narrow policy ranges.
    /// - Parameter width: The meter's width in points, at least the outline width.
    /// - Returns: Low and high tick centres, inset so neither outline is clipped.
    public func targetTickPositions(width: Double) -> ClosedRange<Double> {
        let halfOutline = Self.targetTickOutlineWidth / 2
        let separation = min(Self.minimumTickSeparation, max(0, width - 2 * halfOutline))
        let low = max(halfOutline, min(width - halfOutline, width * targetFractions.lowerBound))
        let high = max(halfOutline, min(width - halfOutline, width * targetFractions.upperBound))
        guard high - low < separation else { return low...high }
        let start = max(halfOutline, min(width - halfOutline - separation, (low + high - separation) / 2))
        return start...(start + separation)
    }

    private static func range(_ low: Double?, _ high: Double?, in domain: Double) -> ClosedRange<Double>? {
        guard let low, let high, low <= high else { return nil }
        return max(0, min(1, low / domain))...max(0, min(1, high / domain))
    }
}
