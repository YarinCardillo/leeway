import Foundation
import LeewayCore

/// A measured weekly usage sample, expressed in percentage points.
public struct UsagePoint: Identifiable, Sendable, Equatable {
    public var id: Date { date }
    public let date: Date
    public let used: Double

    public init(date: Date, used: Double) {
        self.date = date
        self.used = used
    }
}

public typealias UsageStatus = AccountRisk

/// Presentation data supplied by a usage reader. No credentials enter this model.
public struct AccountUsage: Identifiable, Sendable, Equatable {
    public let id: String
    public var name: String
    public let source: String
    public var weeklyUsed: Double?
    public let fiveHourUsed: Double?
    public let reset: Date?
    public let fiveHourReset: Date?
    public let weekForecast: Double?
    public let recentForecast: Double?
    public let recordedAt: Date?
    public let history: [UsagePoint]
    public var targetLow: Double = 75
    public var targetHigh: Double = 100
    public var exhaustsAt: Date?
    public var isEnabled = true
    public var isStale = false
    public var error: AccountReadError?
    public var folder: String = ""
    public var aliases: [String] = []
    public var defaultName: String?

    public var hasDefaultName: Bool { name == defaultName }

    /// A failed attempt does not make a recent successful reading old.
    public func isReadingOld(pollingMinutes: Int, now: Date = Date()) -> Bool {
        guard weeklyUsed != nil, let recordedAt else { return false }
        return now.timeIntervalSince(recordedAt) > Double(pollingMinutes * 120)
    }

    public var lowerForecast: Double? {
        guard let weeklyUsed, let weekForecast else { return nil }
        return max(weeklyUsed, min(weekForecast, recentForecast ?? weekForecast))
    }
    public var upperForecast: Double? {
        guard let weeklyUsed, let weekForecast else { return nil }
        return max(weeklyUsed, weekForecast, recentForecast ?? weekForecast)
    }
    public var status: UsageStatus {
        AccountRisk.evaluate(low: lowerForecast, high: upperForecast, targetLow: targetLow, targetHigh: targetHigh)
    }
    public var hoursEarly: Double? { status.hoursEarly(exhaustsAt: exhaustsAt, reset: reset) }
    public var severity: RiskSeverity? { status.severity(hoursEarly: hoursEarly) }
    public var priority: Int {
        switch status {
        case .over: severity == .red ? 3 : 2
        case .under: 1
        case .onTarget: 0
        }
    }

    public init(id: String, name: String, source: String, weeklyUsed: Double?,
                fiveHourUsed: Double?, reset: Date?, fiveHourReset: Date?,
                weekForecast: Double?, recentForecast: Double?, recordedAt: Date?,
                history: [UsagePoint]) {
        self.id = id
        self.name = name
        self.source = source
        self.weeklyUsed = weeklyUsed
        self.fiveHourUsed = fiveHourUsed
        self.reset = reset
        self.fiveHourReset = fiveHourReset
        self.weekForecast = weekForecast
        self.recentForecast = recentForecast
        self.recordedAt = recordedAt
        self.history = history
    }
}

/// The app's boundary to the core. Refresh returns the last good data with per-account stale flags.
@MainActor
public protocol UsageProvider {
    func refresh() async throws -> [AccountUsage]
    func loadSettings(_ stored: AppPreferences) throws -> AppPreferences
    func saveSettings(_ preferences: AppPreferences, accounts: [AccountUsage]) throws
}

public extension UsageProvider {
    func loadSettings(_ stored: AppPreferences) throws -> AppPreferences { stored }
    func saveSettings(_ preferences: AppPreferences, accounts: [AccountUsage]) throws {}
}
