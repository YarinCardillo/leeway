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
    try usageCache(used: 99).write(to: folder.appendingPathComponent(sliceName("sand.client.slice.account.new.transcript.replicas.x")),
        atomically: true, encoding: .utf8)
    let snapshot = try #require(try GrokBotReader.read(home: home, account: "grok-default"))
    #expect(snapshot.sevenDay.pct == 4.1)
    #expect(abs((snapshot.sevenDay.resetsAt ?? .distantPast).timeIntervalSince(reset)) < 0.001)
    #expect(abs(snapshot.at.timeIntervalSince(now)) < 0.001)
    #expect(snapshot.plan == "Super")
    #expect(snapshot.fiveHour == UsageWindow())
}

@Test func grokBotMissingFolderOrAbsentReadingReturnsNothing() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(try GrokBotReader.read(home: home, account: "grok-default") == nil)
    let folder = try persistence(home)
    try #"{"schemaVersion":3,"value":{"kind":"absent"}}"#
        .write(to: folder.appendingPathComponent(sliceName("sand.client.slice.account.a.weekly-usage.cache")), atomically: true, encoding: .utf8)
    #expect(try GrokBotReader.read(home: home, account: "grok-default") == nil)
}

@Test func grokBotCapsTheIncludedWindowAndRejectsNegativeUsage() {
    #expect(GrokBotReader.parse(Data(usageCache(used: 130).utf8), account: "grok")?.sevenDay.pct == 100)
    #expect(GrokBotReader.parse(Data(usageCache(used: -1).utf8), account: "grok") == nil)
}

@Test func grokBotFolderIsDiscoveredButNeverOfferedToAgents() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(GrokBotReader.defaultFolder), withIntermediateDirectories: true)
    let found = try TargetDiscovery.discover(home: home, accounts: [], environment: [:])
    #expect(found.map(\.id) == ["grok-default"])
    #expect(found.map(\.label) == ["Grok Bot"])
    #expect(!Provider.grok.isAgent && Provider.claude.isAgent && Provider.codex.isAgent)
}
