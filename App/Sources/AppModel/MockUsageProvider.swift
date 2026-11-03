import Foundation

/// Deterministic sample data for previews and the explicit --mock launch argument.
@MainActor
public struct MockUsageProvider: UsageProvider {
    private let now: Date

    public init(now: Date = Date()) { self.now = now }

    public func refresh() async throws -> [AccountUsage] {
        [sample(id: "sample-work", name: "Work", source: "Claude Code", used: 71, forecast: 104, recent: 118),
         sample(id: "sample-personal", name: "Personal", source: "Claude Code", used: 38, forecast: 78, recent: 86),
         sample(id: "sample-codex", name: "Codex", source: "Codex", used: 12, forecast: 31, recent: 40)]
    }

    private func sample(id: String, name: String, source: String,
                        used: Double, forecast: Double, recent: Double) -> AccountUsage {
        let history = (0...4).map { day in
            UsagePoint(date: now.addingTimeInterval(Double(day - 4) * 86400), used: used * Double(day + 1) / 5)
        }
        return AccountUsage(id: id, name: name, source: source, weeklyUsed: used,
                            fiveHourUsed: 18, reset: now.addingTimeInterval(3 * 86400),
                            fiveHourReset: now.addingTimeInterval(7200), weekForecast: forecast,
                            recentForecast: recent, recordedAt: now, history: history)
    }
}
