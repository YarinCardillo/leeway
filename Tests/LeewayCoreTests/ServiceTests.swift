import Foundation
import Testing
@testable import LeewayCore

@Test func cachedServiceNeverProbesAndExplicitRefreshRecordsHistory() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    let store = try SnapshotStore(path: ":memory:")
    let runner = FakeRunner(output: ProcessOutput(exitCode: 0, stdout: rateEvent(week: 0.5)))
    let service = UsageService(home: home, policy: Policy(), store: store, runner: runner, environment: [:], clock: { now })
    let empty = try await service.status()
    #expect(empty.accounts.first?.stale == true)
    #expect(empty.accounts.first?.sevenDay.pct == nil)
    #expect(runner.calls.isEmpty)
    let fresh = try await service.status(refresh: true)
    #expect(fresh.accounts.first?.sevenDay.pct == 50)
    #expect(fresh.history["claude-default"]?.map(\.pct) == [50])
    #expect(runner.calls.count == 2)
    let cached = try await service.status()
    #expect(cached.accounts.first?.stale == false)
    #expect(runner.calls.count == 2)
}

@Test func failedRefreshRetainsGoodReadingAndExpiredWindowsAreEmpty() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    let store = try SnapshotStore(path: ":memory:")
    try store.record(Snapshot(account: "claude-default", at: now.addingTimeInterval(-24 * hour),
        sevenDay: UsageWindow(pct: 80, resetsAt: reset)))
    try store.record(Snapshot(account: "claude-default", at: now.addingTimeInterval(-100),
        fiveHour: UsageWindow(pct: 80, resetsAt: now.addingTimeInterval(-1)), sevenDay: UsageWindow(pct: 40, resetsAt: reset)))
    let service = UsageService(home: home, policy: Policy(), store: store, runner: FakeRunner(), environment: [:], clock: { now })
    let document = try await service.status(refresh: true)
    #expect(document.accounts.first?.stale == true)
    #expect(document.accounts.first?.sevenDay.pct == 40)
    #expect(document.accounts.first?.fiveHour == UsageWindow())
    #expect(try await service.status().accounts.first?.stale == true)
}

@Test func statusKeepsDistinctPathsDespiteSimilarQuotas() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let configs = ["first", "alias", "second"].map {
        AccountConfiguration(id: $0, provider: $0 == "second" ? .codex : .claude, configDir: home.appendingPathComponent($0))
    }
    for config in configs { try FileManager.default.createDirectory(at: config.configDir, withIntermediateDirectories: true) }
    let store = try SnapshotStore(path: ":memory:")
    for (index, config) in configs.enumerated() {
        try store.record(Snapshot(account: config.id, at: now, sevenDay: UsageWindow(pct: 50 + Double(index), resetsAt: reset)))
    }
    let service = UsageService(home: home, policy: Policy(accounts: configs), store: store, runner: FakeRunner(), environment: [:], clock: { now })
    let document = try await service.status()
    #expect(document.accounts.map(\.id) == ["first", "alias", "second"])
    #expect(document.accounts.allSatisfy { $0.aliases.isEmpty })
}

@Test func codexOldLogsStayFreshAndRefreshIsSerialized() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let sessions = home.appendingPathComponent(".codex/sessions")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    try codexLine(at: now.addingTimeInterval(-8 * hour)).write(to: sessions.appendingPathComponent("rollout-one.jsonl"), atomically: true, encoding: .utf8)
    let runner = FakeRunner()
    let service = UsageService(home: home, policy: Policy(), store: try SnapshotStore(path: ":memory:"), runner: runner, environment: [:], clock: { now })
    let document = try await service.status()
    #expect(document.accounts.first?.stale == false)
    #expect(document.accounts.first?.sevenDay.pct == 9)
    #expect(runner.calls.isEmpty)
}

@Test(arguments: [
    "{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"allowed\"}}",
    "{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"unifiedWindows\":{\"seven_day\":{\"utilization\":0.1}}}}"
])
func malformedRefreshCannotEraseRetainedUsageOrBypassCeiling(_ output: String) async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    let store = try SnapshotStore(path: ":memory:")
    try store.record(Snapshot(account: "claude-default", at: now.addingTimeInterval(-24 * hour),
        sevenDay: UsageWindow(pct: 80, resetsAt: reset)))
    try store.record(Snapshot(account: "claude-default", at: now.addingTimeInterval(-100),
        sevenDay: UsageWindow(pct: 98, resetsAt: reset)))
    let service = UsageService(home: home, policy: Policy(), store: store,
        runner: FakeRunner(output: ProcessOutput(exitCode: 0, stdout: output)), environment: [:], clock: { now })
    let status = try await service.status(refresh: true)
    #expect(status.accounts.first?.sevenDay.pct == 98)
    #expect(status.accounts.first?.stale == true)
    let advice = try await service.advise(AdviceRequest(repo: "/example", role: .builder, taskClass: .integration, agent: .claude))
    #expect(advice.verdict == .wait)
}

@Test(arguments: [Provider.claude, .codex], [true, false])
func finding2PartialReadingRetainsEachWindowAndBlocks(provider: Provider, missingWeek: Bool) async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let directory = home.appendingPathComponent("profile")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let config = AccountConfiguration(id: "guarded", provider: provider, configDir: directory, overTarget: .block)
    let store = try SnapshotStore(path: ":memory:")
    let old = now.addingTimeInterval(-100)
    if missingWeek {
        try store.record(Snapshot(account: config.id, at: now.addingTimeInterval(-24 * hour),
            sevenDay: UsageWindow(pct: 80, resetsAt: reset)))
    }
    try store.record(Snapshot(account: config.id, at: old,
        fiveHour: UsageWindow(pct: missingWeek ? 5 : 99, resetsAt: now.addingTimeInterval(hour)),
        sevenDay: UsageWindow(pct: missingWeek ? 98 : 20, resetsAt: reset)))
    let output: String
    if provider == .claude {
        output = missingWeek
            ? rateEvent().replacingOccurrences(of: "\"seven_day\":", with: "\"ignored\":")
            : rateEvent(week: 0.2).replacingOccurrences(of: "\"five_hour\":", with: "\"ignored\":")
    } else {
        output = codexLine(week: 20).replacingOccurrences(of: missingWeek ? "\"secondary\":" : "\"primary\":", with: "\"ignored\":")
        let sessions = directory.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try output.write(to: sessions.appendingPathComponent("rollout-one.jsonl"), atomically: true, encoding: .utf8)
    }
    let service = UsageService(home: home, policy: Policy(accounts: [config]), store: store,
        runner: FakeRunner(output: ProcessOutput(exitCode: 0, stdout: output)), environment: [:], clock: { now })
    let before = try await service.advise(AdviceRequest(repo: "/example", role: .builder, taskClass: .integration, agent: provider))
    #expect(before.verdict == (missingWeek ? .deny : .wait))
    let status = try await service.status(refresh: true)
    let account = try #require(status.accounts.first)
    #expect(account.sevenDay.pct == (missingWeek ? 98 : 20))
    #expect(account.fiveHour.pct == (missingWeek ? (provider == .claude ? 5 : 2) : 99))
    #expect(account.stale)
    #expect(account.asOf == old)
    let advice = try await service.advise(AdviceRequest(repo: "/example", role: .builder, taskClass: .integration, agent: provider))
    #expect(advice.verdict == (missingWeek ? .deny : .wait))
    if missingWeek { #expect(status.history[config.id] == [HistoryPoint(at: now.addingTimeInterval(-24 * hour), pct: 80), HistoryPoint(at: old, pct: 98)]) }
}

@Test func finding3MatchingQuotaDoesNotMergePolicyIdentities() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let configs = [AccountConfiguration(id: "open", provider: .claude, configDir: home.appendingPathComponent("open"), targetHigh: 100),
        AccountConfiguration(id: "restricted", provider: .claude, configDir: home.appendingPathComponent("restricted"), targetLow: 40, targetHigh: 50, overTarget: .block)]
    let store = try SnapshotStore(path: ":memory:")
    for (index, config) in configs.enumerated() {
        try FileManager.default.createDirectory(at: config.configDir, withIntermediateDirectories: true)
        try store.record(Snapshot(account: config.id, at: now,
            fiveHour: UsageWindow(pct: index == 0 ? 5 : 99, resetsAt: now.addingTimeInterval(hour)),
            sevenDay: UsageWindow(pct: 60, resetsAt: reset)))
    }
    let service = UsageService(home: home, policy: Policy(accounts: configs), store: store, runner: FakeRunner(), environment: [:], clock: { now })
    let status = try await service.status()
    #expect(status.accounts.map(\.id) == ["open", "restricted"])
    #expect(status.accounts.allSatisfy { $0.aliases.isEmpty })
    #expect(status.accounts.last?.targetHigh == 50)
    #expect(status.accounts.last?.fiveHour.pct == 99)
    let advice = try await service.advise(AdviceRequest(repo: "/example", role: .builder, taskClass: .integration, agent: .claude, account: "restricted"))
    #expect(advice.verdict != .go)
    #expect(advice.configDir == configs[1].configDir.path)
}

final class DelayedRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var probes = 0
    var count: Int { lock.withLock { probes } }
    func run(_ request: ProcessRequest) throws -> ProcessOutput {
        if request.arguments.first == "auth" { return ProcessOutput(exitCode: 0, stdout: "{}") }
        lock.withLock { probes += 1 }
        Thread.sleep(forTimeInterval: 0.3)
        return ProcessOutput(exitCode: 0, stdout: rateEvent(week: 0.5))
    }
}

@Test func finding5ConcurrentRefreshesShareOneProbeAndServeCachedAdvice() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    let runner = DelayedRunner(), store = try SnapshotStore(path: ":memory:")
    try store.record(Snapshot(account: "claude-default", at: now.addingTimeInterval(-24 * hour),
        sevenDay: UsageWindow(pct: 80, resetsAt: reset)))
    try store.record(Snapshot(account: "claude-default", at: now.addingTimeInterval(-100),
        fiveHour: UsageWindow(pct: 5, resetsAt: reset), sevenDay: UsageWindow(pct: 98, resetsAt: reset)))
    let service = UsageService(home: home, policy: Policy(), store: store, runner: runner, environment: [:], clock: { now })
    async let first = service.status(refresh: true)
    while runner.count == 0 { try await Task.sleep(for: .milliseconds(5)) }
    async let second = service.status(refresh: true)
    let start = Date()
    let advice = try await service.advise(AdviceRequest(repo: "/example", role: .builder, taskClass: .integration, agent: .claude))
    #expect(Date().timeIntervalSince(start) < 0.15)
    #expect(advice.verdict == .wait)
    let readings = try await [first, second]
    #expect(readings.allSatisfy { $0.accounts.first?.sevenDay.pct == 50 })
    #expect(runner.count == 1)
}

@Test func deduplicatedFoldersKeepTheUnionOfTheirWeeklyHistories() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let directory = home.appendingPathComponent("work")
    let alias = home.appendingPathComponent("profile")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
    let configurations = [AccountConfiguration(id: "work", provider: .claude, label: "Work", configDir: directory),
        AccountConfiguration(id: "old-profile", provider: .claude, configDir: alias)]
    let store = try SnapshotStore(path: ":memory:")
    for (id, offset, used) in [("old-profile", -7200.0, 10.0), ("old-profile", -3600.0, 20.0), ("work", -3600.0, 21.0), ("work", 0.0, 30.0)] {
        try store.record(Snapshot(account: id, at: now.addingTimeInterval(offset), sevenDay: UsageWindow(pct: used, resetsAt: reset)))
    }
    let service = UsageService(home: home, policy: Policy(accounts: configurations), store: store, runner: FakeRunner(), environment: [:], clock: { now })
    let document = try await service.status()
    #expect(document.accounts.count == 1)
    #expect(document.accounts.first?.aliases == [alias.path])
    #expect(document.history["work"]?.map(\.pct) == [10, 21, 30])
    #expect(document.history["work"]?.map(\.at) == [now.addingTimeInterval(-7200), now.addingTimeInterval(-3600), now])
}

@Test func freshWeeklyOnlyProbe_HasTimestampAndIsNotStale() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    let output = rateEvent(week: 0.24).replacingOccurrences(of: "\"five_hour\":", with: "\"absent\":")
    let store = try SnapshotStore(path: ":memory:")
    let service = UsageService(home: home, policy: Policy(), store: store,
        runner: FakeRunner(output: ProcessOutput(exitCode: 0, stdout: output)), environment: [:], clock: { now })
    let account = try #require(try await service.status(refresh: true).accounts.first)
    #expect(account.asOf == now)
    #expect(account.sevenDay.pct == 24)
    #expect(!account.stale)
    #expect(try !store.hasFailure(account.id))
}

@Test func codexLogHistory_BurstAfterFlatDay_DoesNotExtrapolatePollingBurst() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let sessions = home.appendingPathComponent(".codex/sessions")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    let readings = [(-24.0, 2.0), (-2, 2), (-1, 8), (0, 13)]
    let lines = readings.map { codexLine(at: now.addingTimeInterval($0.0 * hour), week: $0.1) }
    try lines.joined(separator: "\n").write(to: sessions.appendingPathComponent("rollout-one.jsonl"), atomically: true, encoding: .utf8)
    let store = try SnapshotStore(path: ":memory:")
    let service = UsageService(home: home, policy: Policy(), store: store, runner: FakeRunner(), environment: [:], clock: { now })
    for _ in 0..<2 {
        let document = try await service.status()
        let account = try #require(document.accounts.first)
        #expect(document.history[account.id]?.map(\.pct) == [2, 2, 8, 13])
        #expect(account.forecast.averagePctAtReset == 16.3)
        #expect(account.forecast.recentPctAtReset == 28.6)
        #expect(account.status == .under)
    }
}

@Test func freshWeeklyReading_OldPartialFailureAtSameTimestamp_IsNotStale() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    let store = try SnapshotStore(path: ":memory:")
    try store.record(Snapshot(account: "claude-default", at: now, sevenDay: UsageWindow(pct: 24, resetsAt: reset)))
    // Previous versions marked a successful weekly-only probe as failed at its own timestamp.
    try store.markFailed("claude-default", at: now)
    let service = UsageService(home: home, policy: Policy(), store: store, runner: FakeRunner(), environment: [:], clock: { now })
    let account = try #require(try await service.status().accounts.first)
    #expect(account.asOf == now)
    #expect(!account.stale)
}
