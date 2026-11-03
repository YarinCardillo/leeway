import AppModel
import CryptoKit
import Foundation
import LeewayCore

/// Persists domain settings to the same policy file used by the CLI and advisor.
public struct PolicySettingsStore {
    public let url: URL
    public let home: URL

    public init(url: URL, home: URL) { self.url = url; self.home = home }

    public func load(into stored: AppPreferences) throws -> AppPreferences {
        let policy = try Policy.load(url, home: home)
        var result = stored
        result.pollingMinutes = policy.pollMinutes
        result.accounts = Dictionary(uniqueKeysWithValues: policy.accounts.map {
            var choice = AccountPreference(name: $0.label, isEnabled: $0.isEnabled,
                                           targetLow: $0.targetLow, targetHigh: $0.targetHigh, reserveID: $0.reserveAccount)
            choice.aliases = stored.accounts[$0.id]?.aliases ?? []
            return ($0.id, choice)
        })
        return result
    }

    /// Writes atomically after validating the entire proposed policy with the core parser.
    public func save(_ preferences: AppPreferences, accounts: [AccountUsage], baseline: AppPreferences? = nil) throws {
        let current = try Policy.load(url, home: home)
        let configurations = try mergedAccounts(current.accounts, preferences: preferences, baseline: baseline, readings: accounts)
        let interval = try PolicyAccountEdits.merge(preferences.pollingMinutes,
            baseline: baseline?.pollingMinutes, current: current.pollMinutes)
        let policy = Policy(port: current.port, pollMinutes: interval,
                            codexModel: current.codexModel, roles: current.roles, accounts: configurations,
                            projects: current.projects, defaultAllowed: current.defaultAllowed)
        let text = try PolicyText.encode(policy)
        _ = try Policy.parse(text, home: home)
        try PrivateStorage.write(Data(text.utf8), to: url)
    }

    private func mergedAccounts(_ configured: [AccountConfiguration], preferences: AppPreferences,
                                baseline: AppPreferences?, readings: [AccountUsage]) throws -> [AccountConfiguration] {
        let removed = Set(preferences.folderProviders.keys).subtracting(preferences.addedFolders)
        var result = configured.filter { !removed.contains($0.configDir.path) }
        let reserves = Set(preferences.accounts.values.compactMap(\.reserveID))
        for account in readings where preferences.accounts[account.id] != baseline?.accounts[account.id]
            || reserves.contains(account.id) {
            for path in [account.folder] + account.aliases where !path.isEmpty && !removed.contains(path)
                && !result.contains(where: { $0.configDir.path == path }) {
                result.append(AccountConfiguration(id: path == account.folder ? account.id : stableID(path, prefix: "alias-"),
                    provider: account.source == "Codex" ? .codex : .claude, label: account.name,
                    configDir: URL(fileURLWithPath: path), isEnabled: account.isEnabled, targetLow: account.targetLow, targetHigh: account.targetHigh))
            }
        }
        for folder in preferences.addedFolders where !result.contains(where: { $0.configDir.path == folder }) {
            result.append(AccountConfiguration(id: stableID(folder, prefix: "added-"),
                provider: preferences.folderProviders[folder] == "codex" ? .codex : .claude,
                label: AccountLabel.defaultName(provider: preferences.folderProviders[folder] == "codex" ? .codex : .claude,
                    directory: URL(fileURLWithPath: folder), home: home), configDir: URL(fileURLWithPath: folder)))
        }
        return try result.map { try applyPreferences(preferences, baseline: baseline, to: $0) }
    }

    private func applyPreferences(_ preferences: AppPreferences, baseline: AppPreferences?,
                                  to account: AccountConfiguration) throws -> AccountConfiguration {
        if let owner = preferences.accounts.first(where: { $0.value.aliases.contains(account.configDir.path) }) {
            let original = baseline?.accounts[account.id] ?? AccountPreference(name: account.label,
                isEnabled: account.isEnabled, targetLow: account.targetLow, targetHigh: account.targetHigh, reserveID: account.reserveAccount)
            let desired = PolicyAccountEdits.aliasChoice(owner.value, baseline: baseline?.accounts[owner.key], alias: original)
            return try PolicyAccountEdits.apply(desired, baseline: original, to: account)
        }
        guard let choice = preferences.accounts[account.id] else { return account }
        return try PolicyAccountEdits.apply(choice, baseline: baseline?.accounts[account.id], to: account)
    }

    private func stableID(_ path: String, prefix: String) -> String {
        prefix + SHA256.hash(data: Data(path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
