import AppModel
import Foundation
import LeewayCore

/// Runs the core off the UI actor and shares its policy and SQLite history with the CLI.
@MainActor
public final class CoreUsageProvider: AppModel.UsageProvider {
    private let settings: PolicySettingsStore
    private let makeSource: @Sendable (Policy) throws -> any LeewayCore.UsageProvider
    private let environment: [String: String]
    private var lastPreferences: AppPreferences?
    private var lastReadings: [String: AccountUsage] = [:]
    private var shutdownObserver: ProbeShutdownObserver?

    public init(settings: PolicySettingsStore, environment: [String: String] = [:],
                source: @escaping @Sendable (Policy) throws -> any LeewayCore.UsageProvider) {
        self.settings = settings
        self.environment = environment
        makeSource = source
    }

    /// Uses the same home-relative paths as the command-line service.
    public static func live(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CoreUsageProvider {
        let directory = home.appendingPathComponent("Library/Application Support/leeway", isDirectory: true)
        let store = try SnapshotStore(path: directory.appendingPathComponent("history.sqlite").path)
        let settings = PolicySettingsStore(url: home.appendingPathComponent(".config/leeway/policy.toml"), home: home)
        let processEnvironment = CLIEnvironment.forApplication(home: home, inherited: environment)
        let runner = SystemProcessRunner()
        // One lock for the app's lifetime: each refresh builds a new service, but the app stays the poller.
        let pollLock = PollLock(path: directory.appendingPathComponent("poll.lock").path)
        let provider = CoreUsageProvider(settings: settings, environment: processEnvironment) { policy in
            UsageService(home: home, policy: policy, store: store, runner: runner, environment: processEnvironment,
                         pollLock: pollLock)
        }
        provider.shutdownObserver = ProbeShutdownObserver(runner: runner)
        return provider
    }

    public func refresh() async throws -> [AccountUsage] {
        let policy = try Policy.load(settings.url, home: settings.home)
        let document = try await makeSource(policy).status(refresh: true)
        let book = try accountsCommand(policy).current()
        var readings = CoreSnapshotMapper.map(document, home: settings.home)
        let groupedPaths = lastPreferences?.accounts.values.flatMap(\.aliases) ?? []
        var knownPaths = Set(document.accounts.flatMap { [$0.configDir] + $0.aliases } + groupedPaths)
        for configuration in policy.accounts where !readings.contains(where: { $0.id == configuration.id })
            && !knownPaths.contains(configuration.configDir.path) && !book.isRemoved(configuration.configDir) {
            var account = lastReadings[configuration.id] ?? missing(configuration)
            account.isEnabled = configuration.isEnabled
            account.isStale = true
            account.isFolderMissing = !isDirectory(configuration.configDir)
            readings.append(account)
            knownPaths.insert(configuration.configDir.path)
        }
        for entry in book.ordered where !entry.hidden && !isDirectory(URL(fileURLWithPath: entry.configDir))
            && !knownPaths.contains(entry.configDir) && !readings.contains(where: { $0.id == entry.id }) {
            readings.append(missing(entry))
        }
        lastReadings = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0) })
        return readings
    }

    /// Loads policy settings, copies the app's older account preferences into the shared book once,
    /// and takes the account order from the book.
    public func loadSettings(_ stored: AppPreferences) throws -> AppPreferences {
        var result = try settings.load(into: stored)
        let command = try accountsCommand()
        var book = try command.current()
        if !book.appPreferencesImported {
            book = try command.edit { $0.importAppPreferences(addedFolders: stored.addedFolders.map {
                ($0, stored.folderProviders[$0] == "codex" ? .codex : .claude) }, order: stored.manualAccountOrder) }
        }
        result.addedFolders = []
        result.folderProviders = [:]
        result.manualAccountOrder = book.ordered.map(\.id)
        lastPreferences = result
        return result
    }

    public func saveSettings(_ preferences: AppPreferences, accounts: [AccountUsage]) throws {
        let command = try accountsCommand()
        if let previous = lastPreferences, previous.manualAccountOrder != preferences.manualAccountOrder {
            try command.edit { $0.setOrder(preferences.manualAccountOrder) }
        }
        if let previous = lastPreferences, previous.accounts == preferences.accounts,
           previous.pollingMinutes == preferences.pollingMinutes { return }
        var baseline = lastPreferences
        for account in accounts where baseline?.accounts[account.id] == nil {
            var choice = AccountPreference(name: account.name, isEnabled: account.isEnabled, targetLow: account.targetLow, targetHigh: account.targetHigh)
            choice.aliases = account.aliases
            baseline?.accounts[account.id] = choice
        }
        try settings.save(preferences, accounts: accounts, baseline: baseline, book: command.current())
        lastPreferences = preferences
    }

    public func removeAccount(_ account: AccountUsage) throws {
        let book = try accountsCommand().edit { book in
            if book.accounts.contains(where: { $0.id == account.id }) { try book.remove(id: account.id) }
            else if !account.folder.isEmpty { book.remove(folder: account.folder) }
            else { throw CoreError.accountNotFound }
        }
        try settings.prune(removedIn: book)
    }

    public func addFolder(_ path: String, provider: String) throws {
        guard let kind = Provider(rawValue: provider) else { throw CoreError.invalidRequest("unknown provider") }
        try accountsCommand().edit { try $0.add(folder: path, provider: kind) }
    }

    private func accountsCommand() throws -> AccountsCommand {
        try accountsCommand(Policy.load(settings.url, home: settings.home))
    }

    private func accountsCommand(_ policy: Policy) -> AccountsCommand {
        AccountsCommand(home: settings.home, policy: policy, environment: environment)
    }

    private func missing(_ entry: AccountEntry) -> AccountUsage {
        let folder = URL(fileURLWithPath: entry.configDir)
        let defaultName = AccountLabel.defaultName(provider: entry.provider, directory: folder, home: settings.home)
        var account = AccountUsage(id: entry.id, name: entry.label ?? defaultName,
            source: entry.provider == .codex ? "Codex" : "Claude Code", weeklyUsed: nil,
            fiveHourUsed: nil, reset: nil, fiveHourReset: nil, weekForecast: nil, recentForecast: nil,
            recordedAt: nil, history: [])
        account.defaultName = defaultName
        account.folder = entry.configDir
        account.isStale = true
        account.isFolderMissing = true
        return account
    }

    private func missing(_ configuration: AccountConfiguration) -> AccountUsage {
        var account = AccountUsage(id: configuration.id, name: configuration.label,
            source: configuration.provider == .codex ? "Codex" : "Claude Code", weeklyUsed: nil,
            fiveHourUsed: nil, reset: nil, fiveHourReset: nil, weekForecast: nil, recentForecast: nil,
            recordedAt: nil, history: [])
        account.defaultName = AccountLabel.defaultName(provider: configuration.provider, directory: configuration.configDir, home: settings.home)
        account.folder = configuration.configDir.path
        account.targetLow = configuration.targetLow
        account.targetHigh = configuration.targetHigh
        return account
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
