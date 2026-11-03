import AppModel
import Foundation
import LeewayCore

/// Converts the core's versioned status into presentation values without fabricating missing readings.
public enum CoreSnapshotMapper {
    public static func map(_ document: StatusDocument, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AccountUsage] {
        document.accounts.map { status in
            var account = AccountUsage(id: status.id, name: status.label,
                source: status.provider == .claude ? "Claude Code" : "Codex",
                weeklyUsed: status.sevenDay.pct, fiveHourUsed: status.fiveHour.pct,
                reset: status.sevenDay.resetsAt, fiveHourReset: status.fiveHour.resetsAt,
                weekForecast: status.forecast.averagePctAtReset, recentForecast: status.forecast.recentPctAtReset,
                recordedAt: status.asOf, history: (document.history[status.id] ?? []).map { UsagePoint(date: $0.at, used: $0.pct) })
            account.defaultName = AccountLabel.defaultName(provider: status.provider, directory: URL(fileURLWithPath: status.configDir), home: home)
            account.targetLow = status.targetLow
            account.targetHigh = status.targetHigh
            account.exhaustsAt = status.forecast.exhaustsAt
            account.isStale = status.stale
            account.error = status.error
            account.folder = status.configDir
            account.aliases = status.aliases
            return account
        }
    }
}
