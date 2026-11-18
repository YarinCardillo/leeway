import Foundation
import Testing
@testable import LeewayCore

private final class MovingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var value: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private func transcriptLine(_ at: Date) -> String {
    let formatter = ISO8601DateFormatter()
    return "{\"timestamp\":\"\(formatter.string(from: at))\",\"message\":{\"usage\":{\"input_tokens\":100,\"output_tokens\":100}}}"
}

/// A home with a Claude folder holding a week of fixture transcripts, one message every six hours.
private func homeWithTranscripts() throws -> URL {
    let home = try temporaryDirectory()
    let projects = home.appendingPathComponent(".claude/projects/-fixture-project")
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    let lines = (1...20).map { transcriptLine(now.addingTimeInterval(-Double($0) * 6 * hour)) }
    try lines.joined(separator: "\n").write(to: projects.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
    return home
}

private func service(home: URL, store: SnapshotStore, runner: FakeRunner, clock: MovingClock) -> UsageService {
    UsageService(home: home, policy: Policy(), store: store, runner: runner, environment: [:], clock: { clock.value })
}

@Test func service_NewClaudeAccount_StartsWithEstimatedHistoryAndAForecastAtOnce() async throws {
    let home = try homeWithTranscripts()
    defer { try? FileManager.default.removeItem(at: home) }
    let runner = FakeRunner(output: ProcessOutput(exitCode: 0, stdout: rateEvent(week: 0.3)))
    let service = service(home: home, store: try SnapshotStore(path: ":memory:"), runner: runner, clock: MovingClock(now))
    let document = try await service.status(refresh: true)
    let history = try #require(document.history["claude-default"])
    #expect(history.count > 2)
    #expect(history.filter(\.estimated).count == history.count - 1)
    #expect(history.last == HistoryPoint(at: now, pct: 30))
    #expect(history.filter(\.estimated).allSatisfy { $0.pct <= 30 })
    let account = try #require(document.accounts.first)
    #expect(account.forecast.confidence != .none)
    #expect(account.forecast.averagePctAtReset != nil)
    #expect(account.sevenDay.pct == 30)
}

@Test func service_RealReadingsReplaceTheEstimatedPointsAndTheBackfillRunsOnlyOnce() async throws {
    let home = try homeWithTranscripts()
    defer { try? FileManager.default.removeItem(at: home) }
    let clock = MovingClock(now.addingTimeInterval(-3 * hour))
    let runner = FakeRunner(output: ProcessOutput(exitCode: 0, stdout: rateEvent(week: 0.3)))
    let service = service(home: home, store: try SnapshotStore(path: ":memory:"), runner: runner, clock: clock)
    let first = try #require(try await service.status(refresh: true).history["claude-default"])
    let estimatedCount = first.filter(\.estimated).count
    #expect(estimatedCount > 0)
    clock.advance(hour)
    let second = try #require(try await service.status(refresh: true).history["claude-default"])
    #expect(second.filter(\.estimated).count == estimatedCount, "two real readings keep the backfill, and it is not added twice")
    clock.advance(hour)
    let third = try #require(try await service.status(refresh: true).history["claude-default"])
    #expect(third.filter(\.estimated).isEmpty)
    #expect(third.map(\.pct) == [30, 30, 30])
}

@Test func service_AccountWithExistingReadings_IsNotBackfilled() async throws {
    let home = try homeWithTranscripts()
    defer { try? FileManager.default.removeItem(at: home) }
    let store = try SnapshotStore(path: ":memory:")
    try store.record(Snapshot(account: "claude-default", at: now.addingTimeInterval(-2 * hour),
        sevenDay: UsageWindow(pct: 20, resetsAt: reset)))
    let runner = FakeRunner(output: ProcessOutput(exitCode: 0, stdout: rateEvent(week: 0.3)))
    let document = try await service(home: home, store: store, runner: runner, clock: MovingClock(now)).status(refresh: true)
    #expect(try #require(document.history["claude-default"]).allSatisfy { !$0.estimated })
}

@Test func service_FailedFirstReading_BackfillsNothing() async throws {
    let home = try homeWithTranscripts()
    defer { try? FileManager.default.removeItem(at: home) }
    let store = try SnapshotStore(path: ":memory:")
    let runner = FakeRunner(output: ProcessOutput(exitCode: 1, stdout: "garbage"))
    _ = try await service(home: home, store: store, runner: runner, clock: MovingClock(now)).status(refresh: true)
    #expect(try !store.hasReadings("claude-default"))
}

@Test func service_StatusJson_MarksEstimatedHistoryPoints() async throws {
    let home = try homeWithTranscripts()
    defer { try? FileManager.default.removeItem(at: home) }
    let runner = FakeRunner(output: ProcessOutput(exitCode: 0, stdout: rateEvent(week: 0.3)))
    let document = try await service(home: home, store: try SnapshotStore(path: ":memory:"), runner: runner, clock: MovingClock(now))
        .status(refresh: true)
    let raw = try #require(JSONSerialization.jsonObject(with: JSONCodec.encoder().encode(document)) as? [String: Any])
    let history = try #require((raw["history"] as? [String: [[Any]]])?["claude-default"])
    #expect(history.dropLast().allSatisfy { $0.count == 3 && $0[2] as? Bool == true })
    #expect(history.last?.count == 2)
}
