import Foundation
import Testing
@testable import LeewayCore

@Test func systemRunnerClosesStdinAndReportsOutputAndExit() throws {
    let runner = SystemProcessRunner()
    let request = ProcessRequest(executable: "/bin/cat", arguments: [], environment: [:],
        workingDirectory: FileManager.default.temporaryDirectory, timeout: 1)
    #expect(try runner.run(request).exitCode == 0)
    let output = try runner.run(ProcessRequest(executable: "/usr/bin/printf", arguments: ["hello"], environment: [:],
        workingDirectory: FileManager.default.temporaryDirectory, timeout: 1))
    #expect(output.stdout == "hello")
}

@Test func systemRunnerBoundsTimeoutAndMissingExecutable() throws {
    let runner = SystemProcessRunner()
    let start = Date()
    let output = try runner.run(ProcessRequest(executable: "/bin/sleep", arguments: ["5"], environment: [:],
        workingDirectory: FileManager.default.temporaryDirectory, timeout: 0.05))
    #expect(output.exitCode == 124)
    #expect(Date().timeIntervalSince(start) < 3)
    let missing = try runner.run(ProcessRequest(executable: "/no/such/leeway-command", arguments: [], environment: [:],
        workingDirectory: FileManager.default.temporaryDirectory, timeout: 1))
    #expect(missing.exitCode == 127)
}

@Test func timeoutTerminatesDescendantsThatHoldOutputOpen() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let script = directory.appendingPathComponent("spawn.sh")
    let pidFile = directory.appendingPathComponent("child.pid")
    try "trap '' TERM\nsleep 30 &\nprintf '%s' \"$!\" > \"$1\"\nwait\n".write(to: script, atomically: true, encoding: .utf8)
    let output = try SystemProcessRunner().run(ProcessRequest(executable: "/bin/sh", arguments: [script.path, pidFile.path],
        environment: ["PATH": "/usr/bin:/bin"], workingDirectory: directory, timeout: 0.3))
    #expect(output.exitCode == 124)
    let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)))
    defer { kill(pid, SIGKILL) }
    for _ in 0..<100 {
        if kill(pid, 0) != 0 { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(kill(pid, 0) == -1)
}

@Test func finding10CancellingRefreshTerminatesActiveProbe() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    let script = home.appendingPathComponent("claude"), pidFile = home.appendingPathComponent("pid")
    try "#!/bin/sh\nif [ \"$1\" = auth ]; then printf '{}'; exit; fi\ntrap '' TERM\nprintf '%s' \"$$\" > \"$PROBE_PID\"\nsleep 30\n"
        .write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    let service = UsageService(home: home, policy: Policy(), store: try SnapshotStore(path: ":memory:"),
        runner: SystemProcessRunner(), environment: ["PATH": home.path + ":/usr/bin:/bin", "PROBE_PID": pidFile.path])
    let refresh = Task { try await service.status(refresh: true) }
    for _ in 0..<300 where !FileManager.default.fileExists(atPath: pidFile.path) { try await Task.sleep(for: .milliseconds(10)) }
    let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)))
    defer { kill(-pid, SIGKILL) }
    refresh.cancel()
    for _ in 0..<150 {
        if kill(pid, 0) != 0 { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(kill(pid, 0) == -1)
    kill(-pid, SIGKILL)
    do { _ = try await refresh.value; Issue.record("cancelled refresh succeeded") }
    catch is CancellationError {}
}

@Test func finding10CompletedProbeCannotLeaveDetachedDescendants() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let script = directory.appendingPathComponent("spawn.sh"), file = directory.appendingPathComponent("child.pid")
    try "sleep 60 >/dev/null 2>&1 &\nprintf '%s' \"$!\" > \"$1\"\nprintf ok\n"
        .write(to: script, atomically: true, encoding: .utf8)
    let runner = SystemProcessRunner()
    let output = try runner.run(ProcessRequest(executable: "/bin/sh", arguments: [script.path, file.path],
        environment: ["PATH": "/usr/bin:/bin"], workingDirectory: directory, timeout: 2))
    let pid = try #require(Int32(String(contentsOf: file, encoding: .utf8)))
    defer { kill(pid, SIGKILL) }
    #expect(output.exitCode == 0)
    #expect(output.stdout == "ok")
    runner.shutdown()
    for _ in 0..<100 {
        if kill(pid, 0) != 0 { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(kill(pid, 0) == -1)
}
