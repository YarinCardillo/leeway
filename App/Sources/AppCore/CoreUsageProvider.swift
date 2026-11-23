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
    private let store: SnapshotStore?
    private var lastDataVersion: Int?
    private var lastBookMarker: String
    private var lastValidPolicy: Policy?
    private var storeObserver: (@MainActor () -> Void)?
    private var backgroundTask: Task<Void, Never>?

    /// - Parameter store: The history database the source writes to. With it, `serveBackgroundWork` notices
    ///   readings another process stored and refreshes it served.
    public init(settings: PolicySettingsStore, environment: [String: String] = [:], store: SnapshotStore? = nil,
                source: @escaping @Sendable (Policy) throws -> any LeewayCore.UsageProvider) {
        self.settings = settings
        self.environment = environment
        self.store = store
        lastDataVersion = try? store?.dataVersion()
        lastBookMarker = AccountBookFile(url: AccountBook.fileURL(home: settings.home)).changeMarker()
        lastValidPolicy = try? Policy.load(settings.url, home: settings.home)
        makeSource = source
    }

    deinit { backgroundTask?.cancel() }

    /// Uses the same home-relative paths as the command-line service.
    public static func live(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CoreUsageProvider {
        let directory = home.appendingPathComponent("Library/Application Support/leeway", isDirectory: true)
        let store = try SnapshotStore(path: directory.appendingPathComponent("history.sqlite").path)
        let settings = PolicySettingsStore(url: home.appendingPathComponent(".config/leeway/policy.toml"), home: home)
        let processEnvironment = CLIEnvironment.forApplication(home: home, inherited: environment)
        let runner = SystemProcessRunner()
        let pollLock = PollLock(path: directory.appendingPathComponent("poll.lock").path)
        // One service for the app's lifetime, so a refresh and a request served for another process share one probe.
        let service = UsageService(home: home, policy: (try? Policy.load(settings.url, home: home)) ?? Policy(),
            store: store, runner: runner, environment: processEnvironment, policyFile: settings.url, pollLock: pollLock)
        let provider = CoreUsageProvider(settings: settings, environment: processEnvironment, store: store) { _ in service }
        provider.shutdownObserver = ProbeShutdownObserver(runner: runner)
        provider.startBackgroundWork()
        return provider
    }

    public func refresh() async throws -> [AccountUsage] {
        let policy = try currentPolicy()
        return try readings(from: try await makeSource(policy).status(refresh: true), policy: policy)
    }

    public func scheduledRefresh() async throws -> [AccountUsage] {
        let policy = try currentPolicy()
        let source = try makeSource(policy)
        try await source.pollRound()
        return try readings(from: try await source.status(refresh: false), policy: policy)
    }

    public func reload() async throws -> [AccountUsage] {
        let policy = try currentPolicy()
        return try readings(from: try await makeSource(policy).status(refresh: false), policy: policy)
    }

    public func observeStoreChanges(_ onChange: @escaping @MainActor () -> Void) { storeObserver = onChange }

    /// Starts the background loop: every few seconds it serves refreshes other processes queued while this
    /// app holds the poll lock, and reports readings stored by anyone else. It stops with the provider.
    public func startBackgroundWork(every seconds: TimeInterval = 5) {
        backgroundTask?.cancel()
        backgroundTask = PollingLoop.serveRequests(every: seconds) { [weak self] in await self?.serveBackgroundWork() }
    }

    /// One round of the background loop. Tells the observer when stored readings changed (another process's
    /// commit, or a refresh this round served) or when another process replaced the account book.
    public func serveBackgroundWork() async {
        guard let policy = try? currentPolicy(), let source = try? makeSource(policy) else { return }
        let wasServed = await source.servePendingRefresh()
        let version = try? store?.dataVersion()
        let hasForeignCommit = lastDataVersion != nil && version != lastDataVersion
        lastDataVersion = version
        let marker = AccountBookFile(url: AccountBook.fileURL(home: settings.home)).changeMarker()
        let hasNewBook = marker != lastBookMarker
        lastBookMarker = marker
        if wasServed || hasForeignCommit || hasNewBook { storeObserver?() }
    }

    /// The policy as saved, or the last valid one while the saved file is rejected, so a bad edit never stops
    /// polling. The error itself reaches the user through `loadSettings`.
    private func currentPolicy() throws -> Policy {
        do {
            let policy = try Policy.load(settings.url, home: settings.home)
            lastValidPolicy = policy
            return policy
        } catch {
            guard let lastValidPolicy else { throw error }
            return lastValidPolicy
        }
    }

    private func readings(from document: StatusDocument, policy: Policy) throws -> [AccountUsage] {
        let book = try accountsCommand(policy).current()
        var readings = CoreSnapshotMapper.map(document, home: settings.home)
        let groupedPaths = lastPreferences?.accounts.values.flatMap(\.aliases) ?? []
        var knownPaths = Set(document.accounts.flatMap { [$0.configDir] + $0.aliases } + groupedPaths)
        for configuration in policy.accounts where !readings.contains(where: { $0.id == configuration.id })
            && !knownPaths.contains(configuration.configDir.path) && !book.excludes(configuration.provider, configuration.configDir) {
            var account = lastReadings[configuration.id] ?? missing(configuration, book: book)
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
        for id in result.accounts.keys { result.accounts[id]?.name = book.accounts.first { $0.id == id }?.label }
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
        let baseline = baselinePreferences(accounts)
        try applyRenames(preferences, baseline: baseline, accounts: accounts, command: command)
        // Names live in the book alone, so the policy only ever sees the other settings.
        let desired = withoutNames(preferences), saved = withoutNames(baseline)
        if let previous = withoutNames(lastPreferences), previous.accounts == desired.accounts,
           previous.pollingMinutes == desired.pollingMinutes { return }
        try settings.save(desired, accounts: accounts, baseline: saved, book: command.current())
        lastPreferences = preferences
    }

    private func baselinePreferences(_ accounts: [AccountUsage]) -> AppPreferences? {
        var baseline = lastPreferences
        for account in accounts where baseline?.accounts[account.id] == nil {
            var choice = AccountPreference(name: account.name, isEnabled: account.isEnabled, targetLow: account.targetLow, targetHigh: account.targetHigh)
            choice.aliases = account.aliases
            baseline?.accounts[account.id] = choice
        }
        return baseline
    }

    private func applyRenames(_ preferences: AppPreferences, baseline: AppPreferences?, accounts: [AccountUsage],
                              command: AccountsCommand) throws {
        guard let baseline else { return }
        let renamed = accounts.compactMap { account -> (AccountUsage, String)? in
            guard let name = preferences.accounts[account.id]?.name, name != baseline.accounts[account.id]?.name,
                  !account.folder.isEmpty else { return nil }
            return (account, name)
        }
        guard !renamed.isEmpty else { return }
        try command.edit { book in
            for (account, name) in renamed {
                try book.rename(folder: account.folder, provider: Provider(sourceName: account.source), label: name)
            }
        }
    }

    private func withoutNames(_ preferences: AppPreferences) -> AppPreferences {
        var result = preferences
        for id in result.accounts.keys { result.accounts[id]?.name = nil }
        return result
    }

    private func withoutNames(_ preferences: AppPreferences?) -> AppPreferences? { preferences.map(withoutNames) }

    public func removeAccount(_ account: AccountUsage) throws {
        var prunedPolicy: String?
        // The pruned policy is validated inside the change, so a policy that cannot take it leaves the book as it was.
        try accountsCommand().edit { book in
            if book.accounts.contains(where: { $0.id == account.id }) { try book.remove(id: account.id) }
            else if !account.folder.isEmpty { book.remove(folder: account.folder) }
            else { throw CoreError.accountNotFound }
            prunedPolicy = try settings.pruned(removedIn: book)
        }
        if let prunedPolicy { try settings.write(prunedText: prunedPolicy) }
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
            source: entry.provider.sourceName, weeklyUsed: nil,
            fiveHourUsed: nil, reset: nil, fiveHourReset: nil, weekForecast: nil, recentForecast: nil,
            recordedAt: nil, history: [])
        account.defaultName = defaultName
        account.isRoutable = entry.provider.isAgent
        account.folder = entry.configDir
        account.isStale = true
        account.isFolderMissing = true
        return account
    }

    private func missing(_ configuration: AccountConfiguration, book: AccountBook) -> AccountUsage {
        var account = AccountUsage(id: configuration.id,
            name: book.label(configuration.provider, configuration.configDir) ?? configuration.label,
            source: configuration.provider.sourceName, weeklyUsed: nil,
            fiveHourUsed: nil, reset: nil, fiveHourReset: nil, weekForecast: nil, recentForecast: nil,
            recordedAt: nil, history: [])
        account.defaultName = AccountLabel.defaultName(provider: configuration.provider, directory: configuration.configDir, home: settings.home)
        account.isRoutable = configuration.provider.isAgent
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
