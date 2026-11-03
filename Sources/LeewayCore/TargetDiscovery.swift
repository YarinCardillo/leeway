import Foundation

public enum TargetDiscovery {
    /// Discovers enabled account directories by structure only, resolving aliases without opening auth files.
    public static func discover(home: URL, accounts: [AccountConfiguration], environment: [String: String]) throws -> [Target] {
        var seen = Set(accounts.filter { !$0.isEnabled }.map { key($0.provider, $0.configDir) })
        var targets: [Target] = []
        for account in accounts where account.isEnabled && isDirectory(account.configDir) {
            guard seen.insert(key(account.provider, account.configDir)).inserted else { continue }
            targets.append(Target(id: account.id, provider: account.provider, label: account.label,
                configDir: account.configDir, registered: true))
        }
        var directories: [(Provider, URL, String?)] = [
            (.claude, home.appendingPathComponent(".claude"), "claude-default"),
            (.codex, home.appendingPathComponent(".codex"), "codex-default")]
        directories += try profiles(home).map { (.claude, $0, nil) }
        for (provider, variable) in [(Provider.claude, "CLAUDE_CONFIG_DIR"), (.codex, "CODEX_HOME")] {
            if let value = environment[variable], !value.isEmpty { directories.append((provider, expand(value, home: home), nil)) }
        }
        for (provider, directory, defaultID) in directories where isDirectory(directory) {
            guard seen.insert(key(provider, directory)).inserted else { continue }
            let id = unique(defaultID ?? provider.rawValue + "-" + stableID(directory), targets: targets)
            let label = AccountLabel.defaultName(provider: provider, directory: directory, home: home)
            targets.append(Target(id: id, provider: provider, label: label, configDir: directory))
        }
        return targets
    }

    /// Includes historical IDs only for directories proven to resolve to this target.
    static func historyIDs(for target: Target, home: URL, accounts: [AccountConfiguration]) -> [String] {
        let resolved = target.configDir.resolvingSymlinksInPath()
        var ids = [target.id, target.provider.rawValue + "-" + stableID(target.configDir)]
        let standard = home.appendingPathComponent(".\(target.provider.rawValue)")
        if standard.resolvingSymlinksInPath() == resolved { ids.append(target.provider.rawValue + "-default") }
        ids += accounts.filter {
            $0.provider == target.provider && $0.configDir.resolvingSymlinksInPath() == resolved
        }.map(\.id)
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func profiles(_ home: URL) throws -> [URL] {
        let root = home.appendingPathComponent("Library/Application Support/orca/claude-profiles")
        guard isDirectory(root) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .map { $0.appendingPathComponent("home") }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent(".claude.json").path) }
            .sorted { $0.path < $1.path }
    }

    private static func key(_ provider: Provider, _ directory: URL) -> String {
        provider.rawValue + ":" + directory.resolvingSymlinksInPath().path
    }

    private static func unique(_ base: String, targets: [Target]) -> String {
        var result = base, suffix = 1
        while targets.contains(where: { $0.id == result }) { suffix += 1; result = "\(base)-\(suffix)" }
        return result
    }

    private static func stableID(_ directory: URL) -> String {
        let hash = directory.resolvingSymlinksInPath().path.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
}

func isDirectory(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
}
