import Foundation
import Observation

/// Owns refresh coordination and persistent choices. Views only render this state.
@Observable @MainActor
public final class UsageModel {
    public private(set) var accounts: [AccountUsage] = []
    public private(set) var preferences: AppPreferences
    public private(set) var isRefreshing = false
    public private(set) var hasRefreshed = false
    public private(set) var refreshError: String?
    public private(set) var settingsError: String?
    @ObservationIgnored private var rawAccounts: [AccountUsage] = []
    @ObservationIgnored private var savedPreferences: AppPreferences
    @ObservationIgnored private let provider: any UsageProvider
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    private static let preferencesKey = "app.preferences.v1"

    public init(provider: any UsageProvider, defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.preferencesKey)
            .flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) } ?? AppPreferences()
        var loaded = stored
        var failure: String?
        do { loaded = try provider.loadSettings(stored) }
        catch { failure = "Could not read settings from ~/.config/leeway/policy.toml. Check that the file is readable and valid TOML." }
        preferences = loaded
        savedPreferences = loaded
        settingsError = failure
    }

    public var enabledAccounts: [AccountUsage] {
        accounts.filter(\.isEnabled).sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.upperForecast != $1.upperForecast { return ($0.upperForecast ?? -1) > ($1.upperForecast ?? -1) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public var hasDefaultAccountNames: Bool { accounts.contains(where: \.hasDefaultName) }

    public var selectedAccount: AccountUsage? {
        enabledAccounts.first { $0.id == preferences.pinnedID && $0.weeklyUsed != nil }
            ?? enabledAccounts.first { $0.weeklyUsed != nil }
    }

    /// Coalesces concurrent requests and keeps last successful readings on failure.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; hasRefreshed = true }
        do {
            rawAccounts = try await provider.refresh()
            preferences = try provider.loadSettings(preferences)
            savedPreferences = preferences
            applyPreferences()
            refreshError = nil
        } catch {
            rawAccounts = rawAccounts.map { var account = $0; account.isStale = true; return account }
            applyPreferences()
            refreshError = error.localizedDescription
        }
    }

    public func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                guard let minutes = self?.preferences.pollingMinutes else { return }
                do { try await Task.sleep(for: .seconds(minutes * 60)) } catch { return }
                await self?.refresh()
            }
        }
    }

    public func stopPolling() { pollingTask?.cancel(); pollingTask = nil }
    public func pin(_ id: String?) { preferences.pinnedID = id; save() }

    public func rename(_ name: String, for id: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateAccount(id) { $0.name = trimmed }
    }

    /// Saves bounds together; changed handles use five-point steps while unedited policy fractions survive.
    public func setTarget(low: Double, high: Double, for id: String) {
        guard let account = accounts.first(where: { $0.id == id }),
              (0...100).contains(low), (0...100).contains(high), high - low >= AppPreferences.targetStep,
              low == account.targetLow || low.truncatingRemainder(dividingBy: AppPreferences.targetStep) == 0,
              high == account.targetHigh || high.truncatingRemainder(dividingBy: AppPreferences.targetStep) == 0,
              low != account.targetLow || high != account.targetHigh else { return }
        updateAccount(id) { $0.targetLow = low; $0.targetHigh = high }
    }

    public func setEnabled(_ isEnabled: Bool, for id: String) {
        updateAccount(id) { $0.isEnabled = isEnabled }
    }

    public func setReserve(_ reserveID: String?, for id: String) {
        guard reserveID != id else { return }
        updateAccount(id) { $0.reserveID = reserveID }
    }

    public func setPollingMinutes(_ minutes: Int) {
        guard AppPreferences.pollingChoices.contains(minutes) else { return }
        preferences.pollingMinutes = minutes
        save()
        if pollingTask != nil { startPolling() }
    }

    public func setMenuBarCompact(_ isCompact: Bool) { preferences.isMenuBarCompact = isCompact; save() }

    public func setLanguage(_ language: AppLanguage) { preferences.language = language; save() }
    public func setAutomaticUpdates(_ isEnabled: Bool) { preferences.updatesAutomatically = isEnabled; save() }

    public func addFolder(_ path: String, provider: String = "claude") {
        guard !preferences.addedFolders.contains(path) else { return }
        preferences.addedFolders.append(path)
        preferences.folderProviders[path] = provider
        save()
    }

    public func removeFolder(_ path: String) { preferences.addedFolders.removeAll { $0 == path }; save() }

    private func updateAccount(_ id: String, change: (inout AccountPreference) -> Void) {
        let account = rawAccounts.first { $0.id == id }
        var preference = preferences.accounts[id] ?? AccountPreference(name: account?.name,
            isEnabled: account?.isEnabled ?? true, targetLow: account?.targetLow ?? 75, targetHigh: account?.targetHigh ?? 100)
        preference.aliases = account?.aliases ?? preference.aliases
        change(&preference)
        preferences.accounts[id] = preference
        save()
    }

    private func applyPreferences() {
        accounts = rawAccounts.map { account in
            guard let choice = preferences.accounts[account.id] else { return account }
            var result = account
            result.name = choice.name ?? account.name
            result.targetLow = choice.targetLow
            result.targetHigh = choice.targetHigh
            result.isEnabled = choice.isEnabled
            return result
        }
    }

    private func save() {
        do {
            try provider.saveSettings(preferences, accounts: rawAccounts)
            preferences = try provider.loadSettings(preferences)
            let data = try JSONEncoder().encode(preferences)
            defaults.set(data, forKey: Self.preferencesKey)
            savedPreferences = preferences
            settingsError = nil
        } catch {
            preferences = savedPreferences
            settingsError = "Could not save settings to ~/.config/leeway/policy.toml. Check that the file is writable and valid TOML."
        }
        applyPreferences()
    }
}
