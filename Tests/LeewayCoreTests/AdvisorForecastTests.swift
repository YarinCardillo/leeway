import Foundation
import Testing
@testable import LeewayCore

private func projectedAccount(provider: Provider = .claude, used: Double = 95,
                              projected: Double = 116.5, next: Double = 96, targetHigh: Double = 75) -> AccountStatus {
    AccountStatus(id: "first", label: "First", provider: provider, configDir: "/example/first",
        sevenDay: UsageWindow(pct: used, resetsAt: reset),
        forecast: Forecast(averagePctAtReset: projected, recentPctAtReset: nil,
            rangeLow: projected, rangeHigh: projected, nextRoundPct: next, exhaustsAt: nil, confidence: .low),
        targetLow: targetHigh > 75 ? 75 : targetHigh - 10, targetHigh: targetHigh)
}

@Test func advisorForecast_ReasonUsesMenuForecast_InsteadOfNextRound() {
    let result = ask([projectedAccount()])
    #expect(result.verdict == .wait)
    #expect(result.reason.contains("forecast at 116%"))
    #expect(!result.reason.contains("96%"))
}

@Test func advisorForecast_CodexAboveCeiling_DoesNotGoOnSmallNextRound() {
    let item = projectedAccount(provider: .codex, used: 13, projected: 93, next: 14)
    #expect(item.status == .over)
    let result = ask([item], agent: .codex)
    #expect(result.verdict == .wait)
    #expect(result.reason.contains("forecast at 93%"))
}

@Test func advisorForecast_StatusOK_DoesNotBlockOnNextRound() {
    let item = projectedAccount(provider: .codex, used: 13, projected: 16.3, next: 93)
    #expect(item.status == .under)
    #expect(ask([item], agent: .codex).verdict == .go)
}

@Test func advisorForecast_Weekly95WithinTarget100_Allows() {
    let item = projectedAccount(projected: 95, targetHigh: 100)
    #expect(item.status == .onTarget)
    let result = ask([item])
    #expect(result.verdict == .go)
}

@Test func advisorForecast_AboveCeiling_ExplicitWarnStillAllowsWithForecastWarning() {
    let policy = Policy(accounts: [AccountConfiguration(id: "first", provider: .codex,
        configDir: URL(fileURLWithPath: "/example/first"), overTarget: .warn)])
    let result = ask([projectedAccount(provider: .codex, used: 13, projected: 93, next: 14)], agent: .codex, policy: policy)
    #expect(result.verdict == .go)
    #expect(result.reason.contains("forecast at 93%"))
    #expect(result.reason.contains("warning only"))
}

@Test func advisorForecast_AboveCeiling_SwitchesToSelectedReserve() {
    let policy = Policy(accounts: [AccountConfiguration(id: "first", provider: .codex,
        configDir: URL(fileURLWithPath: "/example/first"), reserveAccount: "reserve")])
    let result = ask([projectedAccount(provider: .codex, used: 13, projected: 93, next: 14),
                      account("reserve", provider: .codex)], agent: .codex, selected: "first", policy: policy)
    #expect(result.verdict == .switch)
    #expect(result.account == "reserve")
    #expect(result.reason.contains("forecast at 93%"))
}

@Test func advisorForecast_NoProjection_AllowsWithoutInventingForecast() {
    let item = account("first", week: 60, next: nil, targetHigh: 50)
    #expect(item.status == .onTarget)
    let result = ask([item])
    #expect(result.verdict == .go)
    #expect(result.reason.contains("60% of its week used"))
    #expect(!result.reason.contains("forecast"))
}
