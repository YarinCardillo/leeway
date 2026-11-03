import Foundation
import Testing
@testable import LeewayCore

func account(_ id: String, provider: Provider = .claude, week: Double? = 20,
             next: Double? = 21, five: Double? = 5, targetHigh: Double = 75,
             weekReset: Date? = reset, fiveReset: Date? = now.addingTimeInterval(hour)) -> AccountStatus {
    AccountStatus(id: id, label: id.capitalized, provider: provider, configDir: "/example/" + id,
        fiveHour: UsageWindow(pct: five, resetsAt: fiveReset), sevenDay: UsageWindow(pct: week, resetsAt: weekReset),
        forecast: Forecast(averagePctAtReset: next, recentPctAtReset: next,
            rangeLow: next, rangeHigh: next, nextRoundPct: next, exhaustsAt: nil, confidence: .low),
        targetLow: targetHigh > 75 ? 75 : targetHigh - 10, targetHigh: targetHigh)
}

func ask(_ accounts: [AccountStatus], role: Role = .builder, agent: Provider? = .claude,
         selected: String? = nil, policy: Policy = Policy()) -> Advice {
    Advisor.advise(AdviceRequest(repo: "/example/app", role: role, taskClass: .integration, agent: agent, account: selected),
        document: StatusDocument(generatedAt: now, accounts: accounts), policy: policy)
}

@Test func preferredAccountGetsGoAndExactCeilingStillAllowed() {
    let result = ask([account("first", next: 75)])
    #expect(result.verdict == .go)
    #expect(result.account == "first")
    #expect(result.model == "sonnet")
    #expect(result.configDir == "/example/first")
}

@Test func overCeilingSwitchesAndAllBlockedWaitForEarliestReset() {
    let result = ask([account("first", next: 76), account("second")])
    #expect(result.verdict == .switch)
    #expect(result.account == "second")
    #expect(result.reason.contains("75% target"))
    let blocked = ask([account("first", next: 99), account("second", five: 97)])
    #expect(blocked.verdict == .wait)
    #expect(blocked.retryAt == now.addingTimeInterval(hour))
}

@Test func noAllowedOrNoKnownResetDeniesAndUnknownUsageAllows() {
    #expect(ask([account("first", next: 99, weekReset: nil)]).verdict == .deny)
    #expect(ask([account("first")], agent: .codex).verdict == .deny)
    let unknown = ask([account("first", week: nil, next: nil)])
    #expect(unknown.verdict == .go)
    #expect(unknown.reason.contains("no reading"))
}

@Test func providerPreferencesAndProjectEligibilityArePreserved() {
    let items = [account("first"), account("second", provider: .codex)]
    #expect(ask(items, agent: nil).agent == "codex")
    #expect(ask(items, role: .reviewer, agent: nil).agent == "codex")
    #expect(ask(items, role: .planner, agent: nil).model == "opus")
    let policy = Policy(defaultAllowed: AllowedAccounts(claude: ["second"]))
    #expect(ask(items, policy: policy).verdict == .deny)
    #expect(ask([account("second", provider: .codex, next: 80), account("first")], agent: nil).verdict == .switch)
}

@Test func reserveAndTargetActionsFollowUserRules() {
    let rule: (TargetAction) -> Policy = { action in
        Policy(accounts: [AccountConfiguration(id: "first", provider: .claude,
            configDir: URL(fileURLWithPath: "/example/first"), reserveAccount: "second", overTarget: action)])
    }
    let items = [account("third"), account("first", next: 90), account("second")]
    #expect(ask(items, selected: "first", policy: rule(.switch)).account == "second")
    #expect(ask(items, selected: "first", policy: rule(.warn)).verdict == .go)
    #expect(ask(items, selected: "first", policy: rule(.block)).verdict == .deny)
    #expect(ask([account("first", five: 95)], policy: rule(.warn)).verdict == .wait)
}

@Test func jsonRoundTripKeepsNullsAndHistoryPairs() throws {
    let doc = StatusDocument(generatedAt: now, accounts: [account("first", week: nil, next: nil)],
        history: ["first": [HistoryPoint(at: now, pct: 20)]])
    let data = try JSONCodec.encoder().encode(doc)
    let raw = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entries = try #require(raw["accounts"] as? [[String: Any]])
    #expect(entries[0]["as_of"] is NSNull)
    let forecast = try #require(entries[0]["forecast"] as? [String: Any])
    #expect(forecast["next_round_pct"] is NSNull)
    #expect(try JSONCodec.decoder().decode(StatusDocument.self, from: data) == doc)
}

@Test func advisorReasonsDistinguishUsedQuotaAndSwitching() {
    #expect(ask([account("first", week: 62)]).reason == "First (claude) has room: 62% of its week used")
    let reason = ask([account("first", next: 88), account("second", week: 62)]).reason
    #expect(reason == "First is forecast at 88% of its week, over its 65%-75% target; switching to Second (claude), 62% of its week used")
}
