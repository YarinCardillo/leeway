import Foundation
import Testing
@testable import LeewayCore

private func targetPolicy(_ fields: String) throws -> AccountConfiguration {
    try Policy.parse("[[accounts]]\nid = \"one\"\nprovider = \"claude\"\nconfig_dir = \"/example/one\"\n" + fields,
                     home: URL(fileURLWithPath: "/example")).accounts[0]
}

@Test func targetPolicy_DefaultAndExplicitBounds() throws {
    let defaults = try targetPolicy("")
    #expect(defaults.targetLow == 75)
    #expect(defaults.targetHigh == 100)
    let full = try targetPolicy("target_low = 0\ntarget_high = 100")
    #expect(full.targetLow == 0)
    #expect(full.targetHigh == 100)
}

@Test(arguments: ["ceiling = 75", "ceiling = 72.5", "ceiling = 95\ntarget_low = 75\ntarget_high = 100"])
func targetPolicy_RejectsCeilingWithTargetGuidance(_ fields: String) {
    do {
        _ = try targetPolicy(fields)
        Issue.record("Obsolete ceiling key was accepted")
    } catch {
        #expect(String(describing: error) == "unknown key: ceiling; use target_low and target_high")
    }
}

@Test func targetPolicy_RejectsOverCeilingWithActionGuidance() {
    do {
        _ = try targetPolicy("over_ceiling = \"warn\"")
        Issue.record("Obsolete over_ceiling key was accepted")
    } catch {
        #expect(String(describing: error) == "unknown key: over_ceiling; use over_target")
    }
}

@Test(arguments: ["target_low = -1", "target_high = 101", "target_low = 100", "target_high = 75",
                  "target_low = 80\ntarget_high = 70", "target_low = true", "target_low = 75\nceiling = 90"])
func targetPolicy_RejectsInvalidOrAmbiguousRange(_ fields: String) {
    #expect(throws: PolicyError.self) { try targetPolicy(fields) }
}

@Test(arguments: [(60.0, 74.9, AccountRisk.under), (70, 75, .onTarget), (70, 84, .onTarget),
                   (75, 100, .onTarget), (100, 110, .onTarget), (100.1, 110, .over)])
func targetVerdict_UsesEntireForecastRange(_ low: Double, _ high: Double, _ expected: AccountRisk) {
    #expect(AccountRisk.evaluate(low: low, high: high, targetLow: 75, targetHigh: 100) == expected)
}

@Test func targetVerdict_UnknownForecastIsNeutral() {
    #expect(AccountRisk.evaluate(low: nil, high: nil, targetLow: 75, targetHigh: 100) == .onTarget)
}

private func rangeAccount(_ low: Double?, _ high: Double?, targetHigh: Double = 100,
                          hoursEarly: Double? = nil) -> AccountStatus {
    AccountStatus(id: "one", label: "One", provider: .claude, configDir: "/example/one",
        sevenDay: UsageWindow(pct: 62, resetsAt: reset),
        forecast: Forecast(averagePctAtReset: low, recentPctAtReset: high, rangeLow: low, rangeHigh: high,
            nextRoundPct: 63, exhaustsAt: hoursEarly.map { reset.addingTimeInterval(-$0 * hour) }, confidence: .medium),
        targetLow: 75, targetHigh: targetHigh)
}

@Test(arguments: [(0.0, RiskSeverity.amber), (12, .amber), (12.01, .red), (24, .red)])
func targetOver_ReportsEarlyHoursAndSeverity(_ early: Double, _ severity: RiskSeverity) {
    let item = rangeAccount(101, 110, hoursEarly: early)
    #expect(item.status == .over)
    #expect(abs((item.hoursEarly ?? -1) - early) < 0.0001)
    #expect(item.severity == severity)
}

@Test func targetOver_WithoutExhaustionIsAmberWithUnknownHours() {
    let item = rangeAccount(85, 90, targetHigh: 80)
    #expect(item.status == .over)
    #expect(item.hoursEarly == nil)
    #expect(item.severity == .amber)
    let overlap = rangeAccount(70, 110, hoursEarly: 24)
    #expect(overlap.status == .onTarget)
    #expect(overlap.hoursEarly == nil)
    #expect(overlap.severity == nil)
}

@Test func targetStatus_EncodesV3AndExplicitNulls() throws {
    let data = try JSONCodec.encoder().encode(StatusDocument(generatedAt: now, accounts: [rangeAccount(70, 84)]))
    let raw = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(raw["schema_version"] as? Int == 3)
    let item = try #require((raw["accounts"] as? [[String: Any]])?.first)
    #expect(item["target_low"] as? Double == 75)
    #expect(item["target_high"] as? Double == 100)
    #expect(item["status"] as? String == "on_target")
    #expect(item["hours_early"] is NSNull)
    #expect(item["severity"] is NSNull)
    #expect(item["ceiling"] == nil)
}

@Test func targetAdvisor_UnderGoesWithUnusedTargetPoints() {
    let result = ask([rangeAccount(60, 70)])
    #expect(result.verdict == .go)
    #expect(result.headroomPct == 5)
}

@Test func targetAdvisor_OverlapGoesWithoutHeadroomEvenAbove100() {
    let result = ask([rangeAccount(90, 120)])
    #expect(result.verdict == .go)
    #expect(result.headroomPct == nil)
}

@Test func targetAdvisor_OverWaitsOrDeniesPerPolicy() {
    let item = rangeAccount(101, 120)
    #expect(ask([item]).verdict == .wait)
    let policy = Policy(accounts: [AccountConfiguration(id: "one", provider: .claude,
        configDir: URL(fileURLWithPath: "/example/one"), overTarget: .block)])
    #expect(ask([item], policy: policy).verdict == .deny)
}
