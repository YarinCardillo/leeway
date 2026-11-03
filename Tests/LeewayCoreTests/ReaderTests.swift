import Foundation
import Testing
@testable import LeewayCore

final class FakeRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [ProcessRequest] = []
    let output: ProcessOutput
    init(output: ProcessOutput = ProcessOutput(exitCode: 0, stdout: "")) { self.output = output }
    var calls: [ProcessRequest] { lock.withLock { requests } }
    func run(_ request: ProcessRequest) throws -> ProcessOutput {
        lock.withLock { requests.append(request) }
        if request.arguments.first == "auth" {
            return ProcessOutput(exitCode: 0, stdout: "{\"subscriptionType\":\"max\",\"email\":\"hidden@example.invalid\"}")
        }
        return output
    }
}

func rateEvent(week: Double = 0.94, weekReset: Date = reset) -> String {
    """
    {"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.05,"resetsAt":\(now.addingTimeInterval(hour).timeIntervalSince1970)},"seven_day":{"utilization":\(week),"resetsAt":\(weekReset.timeIntervalSince1970)}}}}
    """
}

@Test func probeUsesIsolatedFlagsSanitizedEnvironmentAndKeepsDeniedEvents() throws {
    let runner = FakeRunner(output: ProcessOutput(exitCode: 1, stdout: "bad line\n" + rateEvent()))
    let home = URL(fileURLWithPath: "/example")
    let target = Target(id: "first", provider: .claude, label: "First", configDir: home.appendingPathComponent("alternate"))
    let reader = ClaudeReader(runner: runner, home: home, environment: [
        "PATH": "/usr/bin", "ANTHROPIC_API_KEY": "test-key", "ANTHROPIC_AUTH_TOKEN": "test-token",
        "CLAUDE_CODE_OAUTH_TOKEN": "test-token", "ANTHROPIC_BASE_URL": "https://example.invalid",
        "CLAUDE_CODE_USE_BEDROCK": "1", "CLAUDE_CODE_USE_VERTEX": "1"], clock: { now })
    let snapshot = try #require(try reader.read(target))
    #expect(snapshot.sevenDay.pct == 94)
    #expect(snapshot.fiveHour.pct == 5)
    #expect(snapshot.plan == "max")
    #expect(snapshot.at == now)
    let probe = try #require(runner.calls.last)
    #expect(probe.arguments == ["-p", "ok", "--output-format", "stream-json", "--verbose", "--model", "haiku",
        "--tools", "", "--system-prompt", "Reply ok.", "--no-session-persistence", "--setting-sources", "",
        "--strict-mcp-config", "--disable-slash-commands"])
    #expect(probe.environment == ["PATH": "/usr/bin", "CLAUDE_CONFIG_DIR": "/example/alternate"])
    #expect(probe.workingDirectory.path != target.configDir.path)
    #expect(!FileManager.default.fileExists(atPath: probe.workingDirectory.path))
}

@Test func defaultClaudeConfigStaysUnsetAndLastEventWins() throws {
    let runner = FakeRunner(output: ProcessOutput(exitCode: 0, stdout: rateEvent(week: 0.1) + "\n" + rateEvent(week: 0.2)))
    let home = FileManager.default.homeDirectoryForCurrentUser
    let target = Target(id: "first", provider: .claude, label: "First", configDir: home.appendingPathComponent(".claude"))
    let reader = ClaudeReader(runner: runner, home: home, environment: ["CLAUDE_CONFIG_DIR": "/other"], clock: { now })
    #expect(try reader.read(target)?.sevenDay.pct == 20)
    #expect(runner.calls.allSatisfy { $0.environment["CLAUDE_CONFIG_DIR"] == nil })
}

@Test func malformedOrBooleanUsageIsUnknownAndLaunchFailureIsSafe() throws {
    let home = URL(fileURLWithPath: "/example")
    let target = Target(id: "first", provider: .claude, label: "First", configDir: home)
    let output = "{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"unifiedWindows\":{\"seven_day\":{\"utilization\":true}}}}"
    let reader = ClaudeReader(runner: FakeRunner(output: ProcessOutput(exitCode: 0, stdout: output)), home: home, environment: [:], clock: { now })
    #expect(try reader.read(target)?.sevenDay.pct == nil)
    let missing = ClaudeReader(runner: FakeRunner(output: ProcessOutput(exitCode: 127, stdout: "private output")), home: home, environment: [:], clock: { now })
    #expect(throws: AccountReadError.cliMissing) { try missing.read(target) }
}

func codexLine(at: Date = now, week: Double = 9, reversed: Bool = false) -> String {
    let five = "{\"used_percent\":2,\"window_minutes\":300,\"resets_at\":\(now.addingTimeInterval(hour).timeIntervalSince1970)}"
    let seven = "{\"used_percent\":\(week),\"window_minutes\":10080,\"resets_at\":\(reset.timeIntervalSince1970)}"
    return """
    {"timestamp":"\(ISO8601DateFormatter().string(from: at))","type":"event_msg","payload":{"type":"token_count","account":"hidden@example.invalid","rate_limits":{"plan_type":"prolite","primary":\(reversed ? seven : five),"secondary":\(reversed ? five : seven)}}}
    """
}

@Test func codexReadsLatestLimitAcrossRolloutsAndIdentifiesWindowLengths() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let sessions = home.appendingPathComponent("sessions/2026/11/02")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    try (codexLine(at: now.addingTimeInterval(-hour), week: 5) + "\n" + codexLine(reversed: true) + "\nmalformed\n")
        .write(to: sessions.appendingPathComponent("rollout-one.jsonl"), atomically: true, encoding: .utf8)
    try codexLine(at: now.addingTimeInterval(-2 * hour), week: 1)
        .write(to: sessions.appendingPathComponent("rollout-two.jsonl"), atomically: true, encoding: .utf8)
    let snapshot = try #require(try CodexReader.read(home: home, account: "second"))
    #expect(snapshot.sevenDay.pct == 9)
    #expect(snapshot.fiveHour.pct == 2)
    #expect(snapshot.plan == "prolite")
    #expect(snapshot.at == now)
    #expect(!(try JSONCodec.string(snapshot)).contains("@"))
}

@Test func codexMissingLogsAndUnrelatedRecordsReturnNothing() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(try CodexReader.read(home: home, account: "second") == nil)
}

@Test(arguments: [-1.0, 101, 1e100])
func codexRejectsOutOfRangePercentages(_ used: Double) throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let sessions = home.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    let line = codexLine(week: used).replacingOccurrences(of: "\"used_percent\":2,", with: "\"used_percent\":\(used),")
    try line.write(to: sessions.appendingPathComponent("rollout-one.jsonl"), atomically: true, encoding: .utf8)
    #expect(try CodexReader.read(home: home, account: "second") == nil)
}

@Test(arguments: [-0.1, 1.01, 1e308])
func claudeRejectsOutOfRangeUtilization(_ used: Double) throws {
    let output = rateEvent(week: used).replacingOccurrences(of: "\"utilization\":0.05,", with: "\"utilization\":\(used),")
    let home = URL(fileURLWithPath: "/example")
    let target = Target(id: "first", provider: .claude, label: "First", configDir: home)
    let reader = ClaudeReader(runner: FakeRunner(output: ProcessOutput(exitCode: 0, stdout: output)), home: home, environment: [:], clock: { now })
    #expect(try reader.read(target) == nil)
}

@Test func finding8AlternateHomeSelectsItsClaudeDirectoryForBothProcesses() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let directory = home.appendingPathComponent(".claude")
    let target = Target(id: "alternate", provider: .claude, label: "Alternate", configDir: directory)
    let runner = FakeRunner(output: ProcessOutput(exitCode: 0, stdout: rateEvent()))
    let reader = ClaudeReader(runner: runner, home: home,
        environment: ["CLAUDE_CONFIG_DIR": "/wrong-account"], clock: { now })
    #expect(try reader.read(target)?.sevenDay.pct == 94)
    #expect(runner.calls.count == 2)
    #expect(runner.calls.allSatisfy { $0.environment["CLAUDE_CONFIG_DIR"] == directory.path })
}
