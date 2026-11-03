import Foundation
import LeewayCore

/// Canonical policy output preserves supported routing rules and account actions.
enum PolicyText {
    static func encode(_ policy: Policy) throws -> String {
        var lines = ["# Settings rewrites this file and drops comments; edit values here or in Settings.",
                     "port = \(policy.port)", "poll_minutes = \(policy.pollMinutes)",
                     "codex_model = \(try quote(policy.codexModel))", "", "[roles]"]
        for key in policy.roles.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            lines.append("\(key.rawValue) = \(try quote(policy.roles[key]!))")
        }
        lines += ["", "[default]"] + (try allowed(policy.defaultAllowed))
        for project in policy.projects {
            lines += ["", "[[projects]]", "name = \(try quote(project.name))", "paths = \(try array(project.paths))"]
            lines += try allowed(project.allowed)
        }
        for account in policy.accounts { lines += try accountLines(account) }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func accountLines(_ account: AccountConfiguration) throws -> [String] {
        var lines = ["", "[[accounts]]", "id = \(try quote(account.id))",
            "provider = \(try quote(account.provider.rawValue))", "label = \(try quote(account.label))",
            "config_dir = \(try quote(account.configDir.path))", "enabled = \(account.isEnabled)",
            "target_low = \(account.targetLow)", "target_high = \(account.targetHigh)",
            "over_target = \(try quote(account.overTarget.rawValue))"]
        if let reserve = account.reserveAccount { lines.append("reserve_account = \(try quote(reserve))") }
        return lines
    }

    private static func allowed(_ accounts: AllowedAccounts) throws -> [String] {
        var lines: [String] = []
        if let claude = accounts.claude { lines.append("claude = \(try array(claude))") }
        if let codex = accounts.codex { lines.append("codex = \(try array(codex))") }
        return lines
    }

    private static func quote(_ value: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func array(_ values: [String]) throws -> String {
        "[" + (try values.map(quote)).joined(separator: ", ") + "]"
    }
}
