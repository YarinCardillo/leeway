import AppModel
import Foundation
import LeewayCore

/// Runs the core off the UI actor and shares its policy and SQLite history with the CLI.
@MainActor
public final class CoreUsageProvider: AppModel.UsageProvider {
    private let settings: PolicySettingsStore
    private let makeSource: @Sendable (Policy) throws -> any LeewayCore.UsageProvider
    private var lastPreferences: AppPreferences?
    private var lastReadings: [String: AccountUsage] = [:]
    private var shutdownObserver: ProbeShutdownObserver?

    public init(settings: PolicySettingsStore,
                source: @escaping @Sendable (Policy) throws -> any LeewayCore.UsageProvider) {
        self.settings = settings
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
        let provider = CoreUsageProvider(settings: settings) { policy in
            UsageService(home: home, policy: policy, store: store, runner: runner, environment: processEnvironment)
        }
        provider.shutdownObserver = ProbeShutdownObserver(runner: runner)
        return provider
    }

    public func refresh() async throws -> [AccountUsage] {
        let policy = try Policy.load(settings.url, home: settings.home)
        let document = try await makeSource(policy).status(refresh: true)
        var readings = CoreSnapshotMapper.map(document, home: settings.home)
        let groupedPaths = lastPreferences?.accounts.values.flatMap(\.aliases) ?? []
        let knownPaths = Set(document.accounts.flatMap { [$0.configDir] + $0.aliases } + groupedPaths)
        for configuration in policy.accounts where !readings.contains(where: { $0.id == configuration.id })
            && !knownPaths.contains(configuration.configDir.path) {
            var account = lastReadings[configuration.id] ?? missing(configuration)
            account.isEnabled = configuration.isEnabled
            account.isStale = true
            readings.append(account)
        }
        lastReadings = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0) })
        return readings
    }

    public func loadSettings(_ stored: AppPreferences) throws -> AppPreferences {
        let result = try settings.load(into: stored)
        lastPreferences = result
        return result
    }

    public func saveSettings(_ preferences: AppPreferences, accounts: [AccountUsage]) throws {
        if let previous = lastPreferences,
           previous.accounts == preferences.accounts, previous.pollingMinutes == preferences.pollingMinutes,
           previous.addedFolders == preferences.addedFolders, previous.folderProviders == preferences.folderProviders { return }
        var baseline = lastPreferences
        for account in accounts where baseline?.accounts[account.id] == nil {
            var choice = AccountPreference(name: account.name, isEnabled: account.isEnabled, targetLow: account.targetLow, targetHigh: account.targetHigh)
            choice.aliases = account.aliases
            baseline?.accounts[account.id] = choice
        }
        try settings.save(preferences, accounts: accounts, baseline: baseline)
        lastPreferences = preferences
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
}
