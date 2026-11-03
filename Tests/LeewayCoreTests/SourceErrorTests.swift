import Foundation
import Testing
@testable import LeewayCore

private struct ErrorCLI: ProcessRunner {
    let auth: ProcessOutput
    let probe: ProcessOutput
    func run(_ request: ProcessRequest) throws -> ProcessOutput {
        request.arguments.first == "auth" ? auth : probe
    }
}

@Test(arguments: [127, 124, 1, 0])
func sourceFailure_SafeReasonRetainsLastReading(_ code: Int) async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    let auth = code == 1 ? "{\"loggedIn\":false,\"email\":\"secret@example.invalid\"}" : "private output"
    let runner = ErrorCLI(auth: ProcessOutput(exitCode: Int32(code), stdout: auth),
                          probe: ProcessOutput(exitCode: 0, stdout: "private output"))
    let store = try SnapshotStore(path: ":memory:")
    let at = now.addingTimeInterval(-60)
    try store.record(Snapshot(account: "claude-default", at: at, sevenDay: UsageWindow(pct: 42, resetsAt: reset)))
    let service = UsageService(home: home, policy: Policy(), store: store, runner: runner, environment: [:], clock: { now })
    let document = try await service.status(refresh: true)
    let account = try #require(document.accounts.first)
    let expected: AccountReadError = code == 127 ? .cliMissing : code == 124 ? .timeout : code == 1 ? .notSignedIn : .invalidOutput
    #expect(account.error == expected)
    #expect(account.sevenDay.pct == 42)
    #expect(account.asOf == at)
    #expect(account.stale)
    #expect(try await service.status().accounts.first?.error == expected)
    let encoded = try JSONCodec.string(document)
    #expect(!encoded.contains("private output"))
    #expect(!encoded.contains("secret@example.invalid"))
}

@Test(arguments: [127, 124, 0])
func probeFailure_ReportsMissingTimeoutOrInvalidOutput(_ code: Int) async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    let runner = ErrorCLI(auth: ProcessOutput(exitCode: 0, stdout: "{\"loggedIn\":true}"),
                          probe: ProcessOutput(exitCode: Int32(code), stdout: "private output"))
    let service = UsageService(home: home, policy: Policy(), store: try SnapshotStore(path: ":memory:"),
                              runner: runner, environment: [:], clock: { now })
    let account = try #require(try await service.status(refresh: true).accounts.first)
    #expect(account.error == (code == 127 ? .cliMissing : code == 124 ? .timeout : .invalidOutput))
    #expect(account.asOf == nil)
}

@Test(arguments: [127, 124, 1, 0])
func fakeExecutable_SafeFailureReachesStatus(_ code: Int) async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    let cli = home.appendingPathComponent("claude")
    try "#!/bin/sh\nprintf '%s' '{\"loggedIn\":false,\"email\":\"secret@example.invalid\"}'\nexit \(code)\n"
        .write(to: cli, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
    let runner = SystemProcessRunner()
    defer { runner.shutdown() }
    let service = UsageService(home: home, policy: Policy(), store: try SnapshotStore(path: ":memory:"),
                              runner: runner, environment: ["PATH": home.path], clock: { now })
    let account = try #require(try await service.status(refresh: true).accounts.first)
    #expect(account.error == (code == 127 ? .cliMissing : code == 124 ? .timeout : .notSignedIn))
}

private final class RecoveringCLI: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0
    func run(_ request: ProcessRequest) throws -> ProcessOutput {
        if request.arguments.first == "auth" { return ProcessOutput(exitCode: 0, stdout: "{\"loggedIn\":true}") }
        let attempt = lock.withLock { attempts += 1; return attempts }
        return ProcessOutput(exitCode: attempt == 1 ? 124 : 0, stdout: attempt == 1 ? "" : rateEvent())
    }
}

@Test func successfulRetry_ClearsSafeError() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    let service = UsageService(home: home, policy: Policy(), store: try SnapshotStore(path: ":memory:"),
                              runner: RecoveringCLI(), environment: [:], clock: { now })
    #expect(try await service.status(refresh: true).accounts.first?.error == .timeout)
    let recovered = try #require(try await service.status(refresh: true).accounts.first)
    #expect(recovered.error == nil)
    #expect(!recovered.stale)
    #expect(recovered.sevenDay.pct == 94)
}
