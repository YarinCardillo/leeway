import Foundation

public enum TargetDiscovery {
    /// Discovers enabled account directories by structure only, resolving aliases without opening auth files.
    /// Folders the book removed or hid are skipped, and the book's folders and names are applied.
    public static func discover(home: URL, accounts: [AccountConfiguration], environment: [String: String],
                                book: AccountBook = AccountBook()) throws -> [Target] {
        try discoverAccounts(home: home, accounts: accounts, environment: environment, book: book).map(\.target)
    }

    /// Like `discover`, and also says how each account was found, so the book can record it.
    public static func discoverAccounts(home: URL, accounts: [AccountConfiguration], environment: [String: String],
                                        book: AccountBook) throws -> [DiscoveredAccount] {
        var seen = Set(accounts.filter { !$0.isEnabled }.map { key($0.provider, $0.configDir) })
        var found: [DiscoveredAccount] = []
        for account in accounts where account.isEnabled && isDirectory(account.configDir) && !book.excludes(account.provider, account.configDir) {
            guard seen.insert(key(account.provider, account.configDir)).inserted else { continue }
            let label = book.label(account.provider, account.configDir) ?? account.label
            found.append(DiscoveredAccount(target: Target(id: account.id, provider: account.provider, label: label,
                configDir: account.configDir, registered: true), origin: .added))
        }
        for entry in book.accounts where entry.origin == .added {
            if let account = saved(entry, home: home, book: book, found: found, seen: &seen) { found.append(account) }
        }
        for (provider, directory, defaultID) in try automaticFolders(home: home, environment: environment)
        where isDirectory(directory) && !book.excludes(provider, directory) {
            guard seen.insert(key(provider, directory)).inserted else { continue }
            let id = unique(defaultID ?? provider.rawValue + "-" + stableID(directory), found: found)
            let label = book.label(provider, directory) ?? AccountLabel.defaultName(provider: provider, directory: directory, home: home)
            found.append(DiscoveredAccount(target: Target(id: id, provider: provider, label: label, configDir: directory), origin: .discovered))
        }
        // Accounts found in another process environment stay in the book and stay visible in this one.
        for entry in book.accounts where entry.origin != .added {
            if let account = saved(entry, home: home, book: book, found: found, seen: &seen) { found.append(account) }
        }
        return found
    }

    private static func saved(_ entry: AccountEntry, home: URL, book: AccountBook, found: [DiscoveredAccount], seen: inout Set<String>) -> DiscoveredAccount? {
        let directory = URL(fileURLWithPath: entry.configDir)
        guard !entry.hidden, isDirectory(directory), !book.isRemoved(directory),
              seen.insert(key(entry.provider, directory)).inserted else { return nil }
        let label = entry.label ?? AccountLabel.defaultName(provider: entry.provider, directory: directory, home: home)
        return DiscoveredAccount(target: Target(id: unique(entry.id, found: found), provider: entry.provider, label: label,
            configDir: directory), origin: entry.origin)
    }

    /// Every account the policy lists, polled or not, so a disabled or missing one can still be listed and removed.
    /// Used with `discoverAccounts`; polling targets come from discovery alone.
    public static func catalogue(home: URL, accounts: [AccountConfiguration], environment: [String: String],
                                 book: AccountBook) throws -> [DiscoveredAccount] {
        var result = try discoverAccounts(home: home, accounts: accounts, environment: environment, book: book)
        for account in accounts where !book.isRemoved(account.configDir)
            && !result.contains(where: { $0.target.configDir.resolvingSymlinksInPath() == account.configDir.resolvingSymlinksInPath()
                && $0.target.provider == account.provider }) {
            let label = book.label(account.provider, account.configDir) ?? account.label
            result.append(DiscoveredAccount(target: Target(id: unique(account.id, found: result), provider: account.provider,
                label: label, configDir: account.configDir, registered: true), origin: .added))
        }
        return result
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

    private static func automaticFolders(home: URL, environment: [String: String]) throws -> [(Provider, URL, String?)] {
        var directories: [(Provider, URL, String?)] = [
            (.claude, home.appendingPathComponent(".claude"), "claude-default"),
            (.codex, home.appendingPathComponent(".codex"), "codex-default")]
        directories += try profiles(home).map { (.claude, $0, nil) }
        for (provider, variable) in [(Provider.claude, "CLAUDE_CONFIG_DIR"), (.codex, "CODEX_HOME")] {
            if let value = environment[variable], !value.isEmpty { directories.append((provider, expand(value, home: home), nil)) }
        }
        return directories
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

    private static func unique(_ base: String, found: [DiscoveredAccount]) -> String {
        var result = base, suffix = 1
        while found.contains(where: { $0.target.id == result }) { suffix += 1; result = "\(base)-\(suffix)" }
        return result
    }

    static func stableID(_ directory: URL) -> String {
        let hash = directory.resolvingSymlinksInPath().path.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
}

func isDirectory(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
}
