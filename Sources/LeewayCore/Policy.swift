import Foundation

public enum Provider: String, Codable, Sendable { case claude, codex }
public enum Role: String, Codable, Sendable { case builder, reviewer, explorer, planner, evaluator }
public enum TaskClass: String, Codable, Sendable { case mechanical, integration, design }
public enum TargetAction: String, Codable, Sendable { case warn, `switch`, block }

public struct AccountConfiguration: Sendable {
    public let id: String
    public let provider: Provider
    public let label: String
    public let configDir: URL
    public let isEnabled: Bool
    public let targetLow: Double
    public let targetHigh: Double
    public let reserveAccount: String?
    public let overTarget: TargetAction

    public init(id: String, provider: Provider, label: String? = nil, configDir: URL,
                isEnabled: Bool = true, targetLow: Double = 75, targetHigh: Double = 100, reserveAccount: String? = nil,
                overTarget: TargetAction = .switch) {
        self.id = id; self.provider = provider; self.label = label ?? AccountLabel.defaultName(provider: provider, directory: configDir); self.configDir = configDir
        self.isEnabled = isEnabled; self.targetLow = targetLow; self.targetHigh = targetHigh
        self.reserveAccount = reserveAccount
        self.overTarget = overTarget
    }
}

public struct AllowedAccounts: Sendable {
    public let claude: [String]?
    public let codex: [String]?
    public init(claude: [String]? = nil, codex: [String]? = nil) { self.claude = claude; self.codex = codex }
}

public struct ProjectPolicy: Sendable {
    public let name: String
    public let paths: [String]
    public let allowed: AllowedAccounts
    public init(name: String, paths: [String], allowed: AllowedAccounts) {
        self.name = name; self.paths = paths; self.allowed = allowed
    }
}

public struct PolicyError: Error, Sendable, CustomStringConvertible {
    public let description: String
    init(_ message: String) { description = message }
}

public struct Policy: Sendable {
    public let port: Int
    public let pollMinutes: Int
    public let codexModel: String
    public let roles: [Role: String]
    public let accounts: [AccountConfiguration]
    public let projects: [ProjectPolicy]
    public let defaultAllowed: AllowedAccounts

    public init(port: Int = 8799, pollMinutes: Int = 15, codexModel: String = "",
                roles: [Role: String] = [:], accounts: [AccountConfiguration] = [],
                projects: [ProjectPolicy] = [], defaultAllowed: AllowedAccounts = AllowedAccounts()) {
        self.port = port; self.pollMinutes = pollMinutes; self.codexModel = codexModel; self.roles = roles
        self.accounts = accounts; self.projects = projects; self.defaultAllowed = defaultAllowed
    }

    /// Loads an optional user policy. Malformed and unreadable files throw PolicyError.
    public static func load(_ url: URL, home: URL) throws -> Policy {
        guard FileManager.default.fileExists(atPath: url.path) else { return Policy() }
        try PrivateStorage.file(url)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw PolicyError("cannot read policy file")
        }
        return try parse(text, home: home)
    }
    /// Parses the documented policy subset of TOML, rejecting unsupported keys and values.
    public static func parse(_ text: String, home: URL) throws -> Policy {
        let raw = try PolicyTOML(text)
        try raw.root.checkKeys(["port", "poll_minutes", "codex_model"])
        let port = try raw.root.integer("port", fallback: 8799)
        let interval = try raw.root.integer("poll_minutes", fallback: 15)
        guard (1...65535).contains(port) else { throw PolicyError("port must be from 1 to 65535") }
        guard [5, 10, 15, 30].contains(interval) else { throw PolicyError("invalid poll_minutes") }
        let roles = try readRoles(raw.roles)
        let accounts = try raw.accounts.map { try readAccount($0, home: home) }
        guard Set(accounts.map(\.id)).count == accounts.count else { throw PolicyError("duplicate account id") }
        for account in accounts {
            if let reserve = account.reserveAccount,
               reserve == account.id || !accounts.contains(where: { $0.id == reserve }) {
                throw PolicyError("reserve_account must name another configured account")
            }
        }
        return try Policy(port: port, pollMinutes: interval, codexModel: raw.root.text("codex_model", fallback: ""),
            roles: roles, accounts: accounts, projects: raw.projects.map { try readProject($0, home: home) },
            defaultAllowed: readAllowed(raw.defaults))
    }
    /// Returns the first project matching the resolved repository or one of its descendants.
    public func allowed(for repo: String) -> AllowedAccounts {
        let path = URL(fileURLWithPath: repo).resolvingSymlinksInPath().path
        return projects.first { project in
            project.paths.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        }?.allowed ?? defaultAllowed
    }

    private static func readRoles(_ table: PolicyTable) throws -> [Role: String] {
        var result: [Role: String] = [:]
        for key in table.keys {
            guard let role = Role(rawValue: key) else { throw PolicyError("unknown role: \(key)") }
            result[role] = try table.text(key)
        }
        return result
    }

    private static func readAccount(_ table: PolicyTable, home: URL) throws -> AccountConfiguration {
        try table.checkKeys(["id", "provider", "label", "config_dir", "enabled", "target_low", "target_high", "reserve_account", "over_target"])
        guard let provider = try Provider(rawValue: table.text("provider")) else { throw PolicyError("invalid provider") }
        guard let action = try TargetAction(rawValue: table.text("over_target", fallback: "switch")) else {
            throw PolicyError("over_target must be warn, switch, or block")
        }
        let target = try readTarget(table)
        let id = try table.text("id")
        let directory = try expand(table.text("config_dir"), home: home)
        let label = try table.text("label", fallback: AccountLabel.defaultName(provider: provider, directory: directory, home: home))
        return try AccountConfiguration(id: id, provider: provider, label: label,
            configDir: directory, isEnabled: table.bool("enabled", fallback: true),
            targetLow: target.low, targetHigh: target.high,
            reserveAccount: table["reserve_account"] == nil ? nil : table.text("reserve_account"), overTarget: action)
    }

    private static func readTarget(_ table: PolicyTable) throws -> (low: Double, high: Double) {
        let low = try table.percentage("target_low", fallback: 75)
        let high = try table.percentage("target_high", fallback: 100)
        guard low < high else { throw PolicyError("target_low must be less than target_high") }
        return (low, high)
    }

    private static func readProject(_ table: PolicyTable, home: URL) throws -> ProjectPolicy {
        try table.checkKeys(["name", "paths", "claude", "codex"])
        guard let paths = try table.strings("paths") else { throw PolicyError("missing project paths") }
        return try ProjectPolicy(name: table.text("name"),
            paths: paths.map { expand($0, home: home).resolvingSymlinksInPath().path },
            allowed: readAllowed(table, project: true))
    }

    private static func readAllowed(_ table: PolicyTable, project: Bool = false) throws -> AllowedAccounts {
        if !project { try table.checkKeys(["claude", "codex"]) }
        return try AllowedAccounts(claude: table.strings("claude"), codex: table.strings("codex"))
    }
}

public struct ModelChoice: Equatable, Sendable {
    public let model: String
    public let effort: String
}

public enum ModelRouter {
    public static func choose(_ provider: Provider, role: Role, task: TaskClass, policy: Policy) -> ModelChoice {
        let pieces = policy.roles[role]?.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let model: String
        var effort = pieces.flatMap { $0.count > 1 ? String($0[1]) : nil } ?? ""
        if let first = pieces?.first { model = String(first) }
        else if role == .planner || role == .evaluator { model = "opus" }
        else if role == .reviewer { model = "sonnet" }
        else {
            model = task == .mechanical ? "haiku" : "sonnet"
            if role == .builder, task == .design { effort = "high" }
        }
        return ModelChoice(model: provider == .codex ? policy.codexModel : model,
            effort: provider == .codex && effort.isEmpty ? "medium" : effort)
    }
}

func expand(_ path: String, home: URL) -> URL {
    if path == "~" { return home }
    return path.hasPrefix("~/") ? home.appendingPathComponent(String(path.dropFirst(2))) : URL(fileURLWithPath: path)
}
