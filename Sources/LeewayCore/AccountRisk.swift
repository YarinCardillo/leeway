import Foundation

public enum RiskSeverity: String, Codable, Sendable { case amber, red }

public enum AccountRisk: String, Codable, Sendable {
    case under, onTarget = "on_target", over

    /// Compares the entire reset forecast with the inclusive target interval.
    public static func evaluate(low: Double?, high: Double?, targetLow: Double, targetHigh: Double) -> Self {
        guard let low, let high else { return .onTarget }
        if high < targetLow { return .under }
        if low > targetHigh { return .over }
        return .onTarget
    }

    /// Hours before reset at which exhaustion is predicted, only for an over-target account.
    public func hoursEarly(exhaustsAt: Date?, reset: Date?) -> Double? {
        guard self == .over, let exhaustsAt, let reset else { return nil }
        return max(0, reset.timeIntervalSince(exhaustsAt) / 3600)
    }

    /// Missing exhaustion evidence is amber; more than twelve hours early is red.
    public func severity(hoursEarly: Double?) -> RiskSeverity? {
        self == .over ? ((hoursEarly ?? 0) > 12 ? .red : .amber) : nil
    }

}
