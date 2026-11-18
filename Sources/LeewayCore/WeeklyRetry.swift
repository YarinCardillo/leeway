import Foundation

/// When an over-target week stops being over if nothing more is used.
enum WeeklyRetry {
    private static let recentWindow: TimeInterval = 24 * 3600
    private static let expiryGrace: TimeInterval = 1

    /// The week is over only while every forecast is above the target, so it clears when the first forecast falls
    /// to it. With the account's history the answer is checked against the samples still eligible at that time:
    /// the recent forecast stops existing once its samples age out, and the average then decides alone. Without
    /// history the forecast is taken as it stands. Never later than the reset.
    static func clearsAt(_ account: AccountStatus, history: [HistoryPoint], now: Date) -> Date? {
        guard let reset = account.sevenDay.resetsAt else { return nil }
        guard let used = account.sevenDay.pct, account.targetHigh > 0 else { return reset }
        let crossing = history.isEmpty
            ? unvalidated(account, used: used, reset: reset, now: now)
            : validated(candidates(account, used: used, history: history, reset: reset, now: now), account, history, reset)
        return max(crossing, now)
    }

    private static func unvalidated(_ account: AccountStatus, used: Double, reset: Date, now: Date) -> Date {
        let crossings = [averageCrossing(account, used: used, reset: reset),
            recentCrossing(account, used: used, reset: reset, now: now)]
        return (crossings.compactMap { $0 } + [reset]).min() ?? reset
    }

    private static func validated(_ moments: [Date?], _ account: AccountStatus, _ history: [HistoryPoint], _ reset: Date) -> Date {
        let sorted = moments.compactMap { $0 }.sorted()
        return sorted.first { !isOver(account, history: history, reset: reset, at: $0) } ?? reset
    }

    /// Every moment the verdict can change: now, each time a recent sample ages out, and the two crossings of
    /// the forecast that holds from each of those moments, plus the reset.
    private static func candidates(_ account: AccountStatus, used: Double, history: [HistoryPoint],
                                   reset: Date, now: Date) -> [Date?] {
        let expiries = history.map { $0.at.addingTimeInterval(recentWindow + expiryGrace) }.filter { $0 > now && $0 < reset }
        let starts = [now] + expiries.sorted()
        let crossings = starts.flatMap { start -> [Date?] in
            let forecast = Forecaster.forecast(history, resetsAt: reset, now: start)
            let held = AccountStatus(id: account.id, label: account.label, provider: account.provider,
                configDir: account.configDir, sevenDay: account.sevenDay, forecast: forecast,
                targetLow: account.targetLow, targetHigh: account.targetHigh)
            return [averageCrossing(held, used: used, reset: reset), recentCrossing(held, used: used, reset: reset, now: start)]
        }
        return starts.map { Optional($0) } + crossings + [reset]
    }

    private static func isOver(_ account: AccountStatus, history: [HistoryPoint], reset: Date, at moment: Date) -> Bool {
        let forecast = Forecaster.forecast(history, resetsAt: reset, now: moment)
        return AccountRisk.evaluate(low: forecast.rangeLow, high: forecast.rangeHigh,
            targetLow: account.targetLow, targetHigh: account.targetHigh) == .over
    }

    /// When the average-pace forecast reaches the target.
    private static func averageCrossing(_ account: AccountStatus, used: Double, reset: Date) -> Date? {
        account.forecast.averagePctAtReset == nil ? nil
            : reset.addingTimeInterval(-Forecaster.week * (1 - used / account.targetHigh))
    }

    /// When the recent-pace forecast reaches the target, if the pace it projects stays as it is.
    private static func recentCrossing(_ account: AccountStatus, used: Double, reset: Date, now: Date) -> Date? {
        let remaining = reset.timeIntervalSince(now)
        guard let recent = account.forecast.recentPctAtReset, remaining > 0, recent > used else { return nil }
        let pace = (recent - used) / remaining
        return reset.addingTimeInterval(-(account.targetHigh - used) / pace)
    }
}
