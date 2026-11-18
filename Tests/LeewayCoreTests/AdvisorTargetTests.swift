import Foundation
import Testing
@testable import LeewayCore

@Test func advise_ForecastOverCallersTarget_WaitsForTheWeeklyReset() {
    let result = ask([account("first", next: 95, targetHigh: 100)], target: 90)
    #expect(result.verdict == .wait)
    #expect(result.retryAt == reset)
    #expect(result.targetUsed == 90)
    #expect(result.reason.contains("90%"))
}

@Test func advise_CallersTargetAboveTheForecast_GoesEvenWhenPolicyWouldWait() {
    let items = [account("first", next: 95, targetHigh: 75), account("second")]
    #expect(ask(items, selected: "first").verdict == .wait)
    let result = ask(items, selected: "first", target: 100)
    #expect(result.verdict == .go)
    #expect(result.account == "first")
    #expect(result.targetUsed == 100)
}

@Test func advise_FirstCandidateOverTheLine_SwitchesToTheSecond() {
    let items = [account("first", next: 95, targetHigh: 100), account("second", next: 40, targetHigh: 100)]
    let result = ask(items, selected: "first", target: 90, candidates: ["first", "second"])
    #expect(result.verdict == .switch)
    #expect(result.account == "second")
}

@Test func advise_Candidates_AreTriedInTheCallersOrderInsteadOfThePolicyReserve() {
    let items = [account("first", next: 10), account("second", next: 10), account("third", next: 10)]
    #expect(ask(items, candidates: ["third", "second"]).account == "third")
    let rule = Policy(accounts: [AccountConfiguration(id: "first", provider: .claude,
        configDir: URL(fileURLWithPath: "/example/first"), reserveAccount: "second")])
    let blocked = [account("first", next: 99, targetHigh: 75), account("second", next: 10), account("third", next: 10)]
    #expect(ask(blocked, selected: "first", policy: rule, candidates: ["third"]).account == "third")
}

@Test func advise_CandidatesNamingNoEligibleAccount_Denies() {
    #expect(ask([account("first")], candidates: ["absent"]).verdict == .deny)
}

@Test func advise_WithoutATarget_PolicyAppliesAndReportsItsTargetHigh() {
    let result = ask([account("first", next: 76, targetHigh: 75), account("second")])
    #expect(result.verdict == .switch)
    #expect(ask([account("first", next: 60, targetHigh: 75)]).targetUsed == 75)
}

@Test func advise_TargetStillRespectsTheFiveHourBlock() {
    #expect(ask([account("first", five: 96)], target: 100).verdict == .wait)
}

@Test func advice_SchemaIsTwoAndCarriesTargetUsed() throws {
    let result = ask([account("first")], target: 80)
    #expect(result.schemaVersion == 2)
    let raw = try #require(jsonObject(try JSONCodec.encoder().encode(result)))
    #expect(raw["schema_version"] as? Int == 2)
    #expect(raw["target_used"] as? Double == 80)
    let none = try #require(jsonObject(try JSONCodec.encoder().encode(ask([], candidates: nil))))
    #expect(none["target_used"] is NSNull)
}

@Test(arguments: [0.0, -5, 100.5, 101, .nan])
func adviceRequest_TargetOutsideOneToHundred_IsRefused(_ target: Double) {
    #expect(throws: CoreError.self) { try AdviceRequest.checkTarget(target) }
}

@Test(arguments: [1.0, 50, 100])
func adviceRequest_TargetInsideOneToHundred_IsAccepted(_ target: Double) throws {
    try AdviceRequest.checkTarget(target)
}

@Test func adviceRequest_ParseReadsTargetAndCandidates() throws {
    let body = Data(#"{"repo":"/x","role":"builder","task_class":"design","target":90,"candidates":["a","b"]}"#.utf8)
    let request = try AdviceRequest.parse(body)
    #expect(request.target == 90)
    #expect(request.candidates == ["a", "b"])
}

@Test(arguments: [#""target":0"#, #""target":101"#, #""target":"90""#, #""candidates":[]"#,
                  #""candidates":[""]"#, #""candidates":"a""#, #""candidates":["a","a"]"#])
func adviceRequest_ParseRefusesInvalidTargetOrCandidates(_ field: String) {
    let body = Data(#"{"repo":"/x","role":"builder","task_class":"design",\#(field)}"#.utf8)
    #expect(throws: CoreError.self) { try AdviceRequest.parse(body) }
}

@Test func httpAdvise_TargetOutOfRange_Returns400() async {
    let router = HTTPRouter(provider: FixtureProvider())
    let body = Data(#"{"repo":"/x","role":"builder","task_class":"design","target":101}"#.utf8)
    let result = await router.handle(HTTPRequest(method: "POST", path: "/v1/advise", headers: ["host": "127.0.0.1:8799"], body: body))
    #expect(result.status == 400)
}

private final class Recorder: @unchecked Sendable { var request: AdviceRequest? }

private struct RecordingProvider: UsageProvider {
    let recorder: Recorder
    func status(refresh: Bool) async throws -> StatusDocument { StatusDocument(generatedAt: now, accounts: []) }
    func advise(_ request: AdviceRequest) async throws -> Advice { recorder.request = request; return ask([]) }
}

@Test func cliAdvise_PassesTargetAndCandidatesToTheProvider() async throws {
    let recorder = Recorder()
    let cli = LeewayCLI(provider: RecordingProvider(recorder: recorder))
    _ = try await cli.run(["advise", "--json", "--repo", "/x", "--role", "builder", "--task-class", "design",
        "--account", "a", "--target", "90", "--candidates", "a,b"])
    #expect(recorder.request?.target == 90)
    #expect(recorder.request?.candidates == ["a", "b"])
    _ = try await cli.run(["advise", "--repo", "/x", "--role", "builder", "--task-class", "design"])
    #expect(recorder.request?.target == nil)
    #expect(recorder.request?.candidates == nil)
}

@Test(arguments: [["--target", "0"], ["--target", "101"], ["--target", "abc"], ["--candidates", ""], ["--candidates", "a,,b"]])
func cliAdvise_InvalidTargetOrCandidates_IsRefused(_ extra: [String]) async {
    let cli = LeewayCLI(provider: RecordingProvider(recorder: Recorder()))
    await #expect(throws: CoreError.self) {
        _ = try await cli.run(["advise", "--repo", "/x", "--role", "builder", "--task-class", "design"] + extra)
    }
}

/// Two recent readings less than six hours apart give an average-only forecast: 40% used halfway through the week.
private func averageOnlyAccount(at moment: Date = now, five: Double = 5, fiveReset: Date = now.addingTimeInterval(hour)) -> AccountStatus {
    let weekReset = now.addingTimeInterval(84 * hour)
    let points = [HistoryPoint(at: now.addingTimeInterval(-3 * hour), pct: 38), HistoryPoint(at: now, pct: 40)]
    return AccountStatus(id: "first", label: "First", provider: .claude, configDir: "/example/first",
        fiveHour: UsageWindow(pct: five, resetsAt: fiveReset), sevenDay: UsageWindow(pct: 40, resetsAt: weekReset),
        forecast: Forecaster.forecast(points, resetsAt: weekReset, now: moment), targetLow: 65, targetHigh: 100)
}

@Test func advise_AverageOnlyForecastOverCallersTarget_WaitsUntilTheAverageFallsToIt() throws {
    let account = averageOnlyAccount()
    #expect(account.forecast.averagePctAtReset == 80)
    #expect(account.forecast.recentPctAtReset == nil)
    let result = ask([account], target: 75)
    #expect(result.verdict == .wait)
    let retry = try #require(result.retryAt)
    #expect(abs(retry.timeIntervalSince(now) - 5.6 * hour) < 60)
    let later = averageOnlyAccount(at: retry.addingTimeInterval(60))
    #expect(ask([later], target: 75).verdict == .go)
}

@Test func advise_ForecastFarOverCallersTarget_StillWaitsForTheWeeklyReset() {
    let account = averageOnlyAccount()
    #expect(ask([account], target: 30).retryAt == now.addingTimeInterval(84 * hour))
}

@Test func advise_FiveHourBlockAndWeeklyCrossing_WaitsForTheLaterOfTheTwo() throws {
    let sooner = ask([averageOnlyAccount(five: 97, fiveReset: now.addingTimeInterval(2 * hour))], target: 75)
    #expect(abs(try #require(sooner.retryAt).timeIntervalSince(now) - 5.6 * hour) < 60)
    let later = ask([averageOnlyAccount(five: 97, fiveReset: now.addingTimeInterval(8 * hour))], target: 75)
    #expect(later.retryAt == now.addingTimeInterval(8 * hour))
}
