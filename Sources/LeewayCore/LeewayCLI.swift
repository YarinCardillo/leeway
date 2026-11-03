import Foundation

/// Handles integration subcommands without reading quota data.
public protocol IntegrationCommand: Sendable {
    func run(_ arguments: [String]) async throws -> String
}

public struct LeewayCLI: Sendable {
    private let provider: any UsageProvider
    private let integrations: (any IntegrationCommand)?

    public init(provider: any UsageProvider, integrations: (any IntegrationCommand)? = nil) {
        self.provider = provider; self.integrations = integrations
    }

    /// Executes an injected CLI command. Returns stdout text and throws safe input/service errors.
    public func run(_ arguments: [String]) async throws -> String {
        let command = arguments.first ?? "help"
        if ["help", "--help", "-h"].contains(command) { return Self.help }
        if command == "integrations" {
            guard let integrations else { throw CoreError.invalidRequest("Integration commands are unavailable in this build. Install the full Leeway CLI.") }
            return try await integrations.run(Array(arguments.dropFirst()))
        }
        let options = try options(Array(arguments.dropFirst()))
        switch command {
        case "status", "refresh":
            try check(options, allowed: ["--json"])
            let document = try await provider.status(refresh: command == "refresh")
            return options["--json"] != nil ? try JSONCodec.string(document) : render(document)
        case "headroom":
            try check(options, allowed: ["--account", "--json"])
            return try await headroom(options)
        case "advise": return try JSONCodec.string(await provider.advise(advice(options)))
        default: throw CoreError.invalidRequest("unknown command \(command): use leeway help")
        }
    }

    public static let help = """
    Usage: leeway [--home PATH] [--policy PATH] COMMAND
      status [--json]             Show the latest cached readings and forecasts.
      headroom --account NAME [--json]
                                 Show unused quota below an account's target.
      advise --repo PATH --role ROLE --task-class CLASS [--agent PROVIDER] [--account NAME]
                                 Recommend an account and model using your rules.
      refresh [--json]            Take a new reading, keeping good data on failure.
      serve                      Poll usage and serve the API on 127.0.0.1.
      integrations install|uninstall
                                 Add or remove opt-in agent hooks.

    Global options:
      --home PATH  Use this home folder for discovery, policy and history.
      --policy PATH  Read rules from this TOML file instead of the default.

    Examples:
      leeway status --json
      leeway headroom --account Work

    """

    private func options(_ arguments: [String]) throws -> [String: String] {
        var values: [String: String] = [:], index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), values[key] == nil else { throw CoreError.invalidRequest("invalid or duplicate option: \(key)") }
            if key == "--json" { values[key] = "true"; index += 1; continue }
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw CoreError.invalidRequest("missing value for \(key)")
            }
            values[key] = arguments[index + 1]
            index += 2
        }
        return values
    }

    private func check(_ options: [String: String], allowed: Set<String>) throws {
        if let key = Set(options.keys).subtracting(allowed).sorted().first {
            throw CoreError.invalidRequest("unknown option: \(key)")
        }
    }

    private func advice(_ options: [String: String]) throws -> AdviceRequest {
        try check(options, allowed: ["--repo", "--role", "--task-class", "--agent", "--account", "--json"])
        guard let repo = options["--repo"], !repo.isEmpty,
              let role = options["--role"].flatMap(Role.init(rawValue:)),
              let task = options["--task-class"].flatMap(TaskClass.init(rawValue:)) else {
            throw CoreError.invalidRequest("advise requires --repo, --role, and --task-class")
        }
        let agent = options["--agent"].flatMap(Provider.init(rawValue:))
        if options["--agent"] != nil, agent == nil { throw CoreError.invalidRequest("invalid agent") }
        return AdviceRequest(repo: repo, role: role, taskClass: task, agent: agent, account: options["--account"])
    }

    private func headroom(_ options: [String: String]) async throws -> String {
        guard let name = options["--account"], !name.isEmpty else { throw CoreError.invalidRequest("headroom requires --account") }
        let matches = try await provider.status(refresh: false).accounts.filter { $0.id == name || $0.label == name }
        guard matches.count == 1, let account = matches.first else { throw CoreError.accountNotFound }
        let headroom = account.sevenDay.pct.map { max(account.targetHigh - $0, 0) }
        if options["--json"] != nil {
            var object: [String: Any] = ["schema_version": 2, "account": account.id, "target_low": account.targetLow, "target_high": account.targetHigh]
            object["used_pct"] = account.sevenDay.pct.map { $0 as Any } ?? NSNull()
            object["headroom_pct"] = headroom.map { $0 as Any } ?? NSNull()
            return String(decoding: try JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
        }
        guard let headroom else { return account.label + ": no reading yet" }
        return account.label + ": " + percent(headroom) + " to target high"
    }

    private func render(_ document: StatusDocument) -> String {
        if document.accounts.isEmpty { return "No accounts found." }
        return document.accounts.map(renderAccount).joined(separator: "\n")
    }

    private func renderAccount(_ account: AccountStatus) -> String {
        let label = account.label + (account.stale ? " (stale)" : "")
        guard let used = account.sevenDay.pct else { return label + ": no reading yet" }
        let forecast = account.forecast.rangeHigh.map { ", forecast " + percent($0) } ?? ""
        return "\(label): \(percent(used)) weekly\(forecast), \(account.status.rawValue.replacingOccurrences(of: "_", with: " "))"
    }

    private func percent(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))%" } ?? "unknown" }
}
