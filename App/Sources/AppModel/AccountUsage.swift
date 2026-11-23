import Foundation
import LeewayCore

/// A measured weekly usage sample, expressed in percentage points.
public struct UsagePoint: Identifiable, Sendable, Equatable {
    public var id: Date { date }
    public let date: Date
    public let used: Double
    /// True for a point estimated from transcripts before the account's first real reading.
    public let isEstimated: Bool

    public init(date: Date, used: Double, isEstimated: Bool = false) {
        self.date = date
        self.used = used
        self.isEstimated = isEstimated
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
    /// True when readings arrive only as the provider records its own work, so a refresh cannot make them newer.
    public var isActivityBased = false
    /// When Leeway last read this account successfully, whether or not the provider had anything new.
    public var checkedAt: Date?
    public var error: AccountReadError?
    public var folder: String = ""
    public var aliases: [String] = []
    public var defaultName: String?
    /// True when the account's folder no longer exists, so no reading can ever arrive.
    public var isFolderMissing = false

    public var hasDefaultName: Bool { name == defaultName }

    /// The five-hour usage while its window is still open. Nil without a reading or once the window has reset,
    /// because a cached value outlives its window until the next reading replaces it.
    public func activeSessionUsed(at now: Date = Date()) -> Double? {
        guard let fiveHourUsed else { return nil }
        guard let fiveHourReset else { return fiveHourUsed }
        return fiveHourReset > now ? fiveHourUsed : nil
    }

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
    /// An explicit refresh the user asked for. A process that does not poll leaves a request for the one that does.
    func refresh() async throws -> [AccountUsage]
    /// The timer's refresh. It takes a reading only in the process that polls and never asks another process for one.
    func scheduledRefresh() async throws -> [AccountUsage]
    /// Reads what is already stored without taking a reading.
    func reload() async throws -> [AccountUsage]
    /// Calls `onChange` when readings were stored that this provider has not returned yet.
    func observeStoreChanges(_ onChange: @escaping @MainActor () -> Void)
    func loadSettings(_ stored: AppPreferences) throws -> AppPreferences
    func saveSettings(_ preferences: AppPreferences, accounts: [AccountUsage]) throws
    /// Removes an account from every client's list, whatever its origin. The folder stays gone until added again.
    func removeAccount(_ account: AccountUsage) throws
    /// Adds a folder to the shared account list.
    func addFolder(_ path: String, provider: String) throws
}

public extension UsageProvider {
    func scheduledRefresh() async throws -> [AccountUsage] { try await refresh() }
    func reload() async throws -> [AccountUsage] { try await refresh() }
    func observeStoreChanges(_ onChange: @escaping @MainActor () -> Void) {}
    func loadSettings(_ stored: AppPreferences) throws -> AppPreferences { stored }
    func saveSettings(_ preferences: AppPreferences, accounts: [AccountUsage]) throws {}
    func removeAccount(_ account: AccountUsage) throws {}
    func addFolder(_ path: String, provider: String) throws {}
}
