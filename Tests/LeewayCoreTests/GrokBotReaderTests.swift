import Foundation
import Testing
@testable import LeewayCore

/// Grok Bot's persistence file name: the slice key, base32 without padding.
private func sliceName(_ key: String) -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
    var bits = 0, value = 0, name = ""
    for byte in Data(key.utf8) {
        value = (value << 8) | Int(byte); bits += 8
        while bits >= 5 { bits -= 5; name.append(alphabet[(value >> bits) & 31]) }
    }
    if bits > 0 { name.append(alphabet[(value << (5 - bits)) & 31]) }
    return name + ".blob"
}

private func usageCache(at: Date = now, used: Double = 4.146, resetsAt: Date = reset) -> String {
    """
    {"schemaVersion":3,"value":{"kind":"present","selectedTeamId":null,"reading":{"usage":{"percentUsed":\(used),\
    "nextResetMs":\(resetsAt.timeIntervalSince1970 * 1000),"isSandTrial":false,"onDemand":{"usedCents":0,"limitCents":1000},\
    "grokPlanLabel":"Grok Bot Plan","unifiedPlanName":"Super"},"readAtMs":\(at.timeIntervalSince1970 * 1000)},"expiresAtMs":0}}
    """
}

/// The clock the reader checks cached times against: an hour after the fixture's reading.
private let readClock = now.addingTimeInterval(hour)

private func persistence(_ home: URL) throws -> URL {
    let folder = home.appendingPathComponent("sand-client-persistence")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Test func grokBotKeysDecodeFromBase32FileNames() {
    let key = "sand.client.slice.account.github%7Cuser_example.weekly-usage.cache"
    #expect(GrokBotReader.key(URL(fileURLWithPath: "/fixture/" + sliceName(key))) == key)
    #expect(GrokBotReader.key(URL(fileURLWithPath: "/fixture/not-base32!.blob")) == nil)
}

@Test func grokBotReadsTheNewestWeeklyUsageCacheAndIgnoresOtherSlices() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let folder = try persistence(home)
    try usageCache(at: now.addingTimeInterval(-hour), used: 1)
        .write(to: folder.appendingPathComponent(sliceName("sand.client.slice.account.old.weekly-usage.cache")), atomically: true, encoding: .utf8)
    try usageCache().write(to: folder.appendingPathComponent(sliceName("sand.client.slice.account.new.weekly-usage.cache")),
        atomically: true, encoding: .utf8)
    try usageCache(at: now.addingTimeInterval(60), used: 99).write(to: folder.appendingPathComponent(sliceName("sand.client.slice.account.new.transcript.replicas.x")),
        atomically: true, encoding: .utf8)
    let snapshot = try #require(try GrokBotReader.read(home: home, account: "grok-default", now: readClock))
    #expect(snapshot.sevenDay.pct == 4.1)
    #expect(abs((snapshot.sevenDay.resetsAt ?? .distantPast).timeIntervalSince(reset)) < 0.001)
    #expect(abs(snapshot.at.timeIntervalSince(now)) < 0.001)
    #expect(snapshot.plan == "Super")
    #expect(snapshot.fiveHour == UsageWindow())
}

@Test func grokBotMissingFolderOrAbsentReadingReturnsNothing() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(try GrokBotReader.read(home: home, account: "grok-default", now: readClock) == nil)
    let folder = try persistence(home)
    try #"{"schemaVersion":3,"value":{"kind":"absent"}}"#
        .write(to: folder.appendingPathComponent(sliceName("sand.client.slice.account.a.weekly-usage.cache")), atomically: true, encoding: .utf8)
    #expect(try GrokBotReader.read(home: home, account: "grok-default", now: readClock) == nil)
}

@Test func grokBotCapsTheIncludedWindowAndRejectsNegativeUsage() {
    #expect(GrokBotReader.parse(Data(usageCache(used: 130).utf8), account: "grok", now: readClock)?.sevenDay.pct == 100)
    #expect(GrokBotReader.parse(Data(usageCache(used: -1).utf8), account: "grok", now: readClock) == nil)
}

@Test func grokBotIsDiscoveredOnceItCachesUsageButNeverOfferedToAgents() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let folder = home.appendingPathComponent(GrokBotReader.defaultFolder)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    #expect(try TargetDiscovery.discover(home: home, accounts: [], environment: [:]).isEmpty)
    try usageCache().write(to: try persistence(folder).appendingPathComponent(sliceName("sand.client.slice.account.a.weekly-usage.cache")),
        atomically: true, encoding: .utf8)
    let found = try TargetDiscovery.discover(home: home, accounts: [], environment: [:])
    #expect(found.map(\.id) == ["grok-default"])
    #expect(found.map(\.label) == ["Grok Bot"])
    #expect(!Provider.grok.isAgent && Provider.claude.isAgent && Provider.codex.isAgent)
}

@Test func grokBotSkipsAnUnreadableSliceAndStillReadsItsSibling() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let folder = try persistence(home)
    let locked = folder.appendingPathComponent(sliceName("sand.client.slice.account.locked.weekly-usage.cache"))
    try usageCache(used: 50).write(to: locked, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: locked.path) }
    try usageCache(at: now.addingTimeInterval(-hour)).write(
        to: folder.appendingPathComponent(sliceName("sand.client.slice.account.open.weekly-usage.cache")), atomically: true, encoding: .utf8)
    let snapshot = try #require(try GrokBotReader.read(home: home, account: "grok-default", now: readClock))
    #expect(snapshot.sevenDay.pct == 4.1)
}

@Test func grokBotIgnoresSymlinksFifosAndOversizedSlices() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let folder = try persistence(home)
    let outside = home.appendingPathComponent("outside.json")
    try usageCache(used: 90).write(to: outside, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(sliceName("sand.client.slice.account.link.weekly-usage.cache")),
        withDestinationURL: outside)
    #expect(mkfifo(folder.appendingPathComponent(sliceName("sand.client.slice.account.pipe.weekly-usage.cache")).path, 0o600) == 0)
    try (usageCache(used: 80) + String(repeating: " ", count: 70 * 1024))
        .write(to: folder.appendingPathComponent(sliceName("sand.client.slice.account.big.weekly-usage.cache")), atomically: true, encoding: .utf8)
    #expect(try GrokBotReader.read(home: home, account: "grok-default", now: readClock) == nil)
}

@Test func grokBotRejectsReadingsFromTheFutureAndImplausibleResets() {
    #expect(GrokBotReader.parse(Data(usageCache(at: readClock.addingTimeInterval(86400)).utf8), account: "grok", now: readClock) == nil)
    #expect(GrokBotReader.parse(Data(usageCache(resetsAt: now.addingTimeInterval(-60)).utf8), account: "grok", now: readClock) == nil)
    #expect(GrokBotReader.parse(Data(usageCache(resetsAt: now.addingTimeInterval(30 * 86400)).utf8), account: "grok", now: readClock) == nil)
    #expect(GrokBotReader.parse(Data(usageCache().utf8), account: "grok", now: readClock) != nil)
}

@Test func grokBotKeepsOnlyAShortPlanLabel() {
    let long = usageCache().replacingOccurrences(of: #""unifiedPlanName":"Super""#,
        with: #""unifiedPlanName":""# + String(repeating: "x", count: 200) + #"""#)
    let snapshot = GrokBotReader.parse(Data(long.utf8), account: "grok", now: readClock)
    #expect(snapshot?.sevenDay.pct == 4.1)
    #expect(snapshot?.plan == nil)
    let marks = usageCache().replacingOccurrences(of: #""unifiedPlanName":"Super""#,
        with: #""unifiedPlanName":"e"# + String(repeating: "\u{301}", count: 2000) + #"""#)
    #expect(GrokBotReader.parse(Data(marks.utf8), account: "grok", now: readClock)?.plan == nil)
}

@Test func httpAdvise_MonitoredOnlyAgent_Returns400() async {
    let router = HTTPRouter(provider: FixtureProvider())
    let body = Data(#"{"repo":"/x","role":"builder","task_class":"design","agent":"grok"}"#.utf8)
    let result = await router.handle(HTTPRequest(method: "POST", path: "/v1/advise", headers: ["host": "127.0.0.1:8799"], body: body))
    #expect(result.status == 400)
    #expect(throws: CoreError.self) { try AdviceRequest.parse(body) }
}
