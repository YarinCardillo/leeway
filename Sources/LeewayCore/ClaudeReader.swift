import Foundation

public struct ClaudeReader: Sendable {
    private let runner: any ProcessRunner
    private let home: URL
    private let environment: [String: String]
    private let clock: @Sendable () -> Date
    private let executable: String
    private let isCancelled: @Sendable () -> Bool

    public init(runner: any ProcessRunner, home: URL, environment: [String: String], executable: String = "claude",
                clock: @escaping @Sendable () -> Date, isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }) {
        self.runner = runner; self.home = home; self.environment = environment; self.executable = executable; self.clock = clock
        self.isCancelled = isCancelled
    }

    /// Runs only the official CLI in a temporary working directory. Process failures expose no output.
    public func read(_ target: Target) throws -> Snapshot? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("leeway-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let env = probeEnvironment(target.configDir)
        let auth = try runner.run(ProcessRequest(executable: executable, arguments: ["auth", "status", "--json"],
            environment: env, workingDirectory: directory, isCancelled: isCancelled))
        try checkExit(auth)
        guard let authentication = jsonObject(Data(auth.stdout.utf8)) else { throw AccountReadError.invalidOutput }
        guard auth.exitCode == 0, authentication["loggedIn"] as? Bool != false else { throw AccountReadError.notSignedIn }
        let plan = authentication["subscriptionType"] as? String
        let done = try runner.run(ProcessRequest(executable: executable, arguments: Self.flags,
            environment: env, workingDirectory: directory, isCancelled: isCancelled))
        try checkExit(done)
        guard let info = lastEvent(done.stdout) else { return nil }
        let windows = info["unifiedWindows"] as? [String: Any] ?? [:]
        let five = window(windows["five_hour"]), week = window(windows["seven_day"])
        guard five.pct != nil || week.pct != nil else { return nil }
        return Snapshot(account: target.id, at: clock(), plan: plan, fiveHour: five, sevenDay: week)
    }

    private func checkExit(_ output: ProcessOutput) throws {
        if output.exitCode == 127 { throw AccountReadError.cliMissing }
        if output.exitCode == 124 { throw AccountReadError.timeout }
    }

    private static let flags = ["-p", "ok", "--output-format", "stream-json", "--verbose", "--model", "haiku",
        "--tools", "", "--system-prompt", "Reply ok.", "--no-session-persistence", "--setting-sources", "",
        "--strict-mcp-config", "--disable-slash-commands"]

    private func probeEnvironment(_ directory: URL) -> [String: String] {
        let removed: Set<String> = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN",
            "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CONFIG_DIR"]
        var env = environment.filter { !removed.contains($0.key) }
        let actualHome = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        if home.resolvingSymlinksInPath() != actualHome
            || directory.resolvingSymlinksInPath() != actualHome.appendingPathComponent(".claude").resolvingSymlinksInPath() {
            env["CLAUDE_CONFIG_DIR"] = directory.path
        }
        return env
    }

    private func lastEvent(_ output: String) -> [String: Any]? {
        var found: [String: Any]?
        for line in output.split(separator: "\n") where line.contains("rate_limit_event") {
            guard let object = jsonObject(Data(line.utf8)), object["type"] as? String == "rate_limit_event",
                  let info = object["rate_limit_info"] as? [String: Any] else { continue }
            found = info
        }
        return found
    }

    private func window(_ raw: Any?) -> UsageWindow {
        guard let raw = raw as? [String: Any] else { return UsageWindow() }
        guard let utilization = quotaNumber(raw["utilization"]), (0...1).contains(utilization),
              let reset = quotaDate(raw["resetsAt"]) else { return UsageWindow() }
        return UsageWindow(pct: rounded(utilization * 100), resetsAt: reset)
    }
}
