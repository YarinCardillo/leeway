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
    @ObservationIgnored private var refreshAfterCurrent = false
    private static let preferencesKey = "app.preferences.v1"

    public init(provider: any UsageProvider, defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        let persisted = defaults.data(forKey: Self.preferencesKey)
        let stored = persisted
            .flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) } ?? AppPreferences()
        var loaded = stored
        var failure: String?
        do {
            loaded = try provider.loadSettings(stored)
            if persisted != nil { defaults.set(try JSONEncoder().encode(loaded), forKey: Self.preferencesKey) }
        }
        catch { failure = "Could not read settings from ~/.config/leeway/policy.toml. Check that the file is readable and valid TOML." }
        preferences = loaded
        savedPreferences = loaded
        settingsError = failure
    }

    public var orderedAccounts: [AccountUsage] {
        preferences.accountOrderMode.ordered(accounts, manualIDs: preferences.manualAccountOrder)
    }

    public var enabledAccounts: [AccountUsage] { orderedAccounts.filter(\.isEnabled) }

    public var hasDefaultAccountNames: Bool { accounts.contains(where: \.hasDefaultName) }

    public var selectedAccount: AccountUsage? { enabledAccounts.first }

    /// Changes the shared order of menu rows and the account shown by the status item.
    public func setAccountOrderMode(_ mode: AccountOrderMode) {
        guard mode != preferences.accountOrderMode else { return }
        if mode == .manual, preferences.manualAccountOrder.isEmpty {
            preferences.manualAccountOrder = orderedAccounts.map(\.id)
        }
        preferences.accountOrderMode = mode
        save()
    }

    /// Applies native List move offsets to the saved manual order.
    /// - Parameters:
    ///   - offsets: Source row indexes in the displayed account list.
    ///   - destination: Insertion offset before removing the source rows.
    public func moveAccounts(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let ids = orderedAccounts.map(\.id)
        guard preferences.accountOrderMode == .manual, !offsets.isEmpty,
              offsets.allSatisfy({ ids.indices.contains($0) }), (0...ids.count).contains(destination) else { return }
        let moved = offsets.sorted().map { ids[$0] }
        var result = ids.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        result.insert(contentsOf: moved, at: destination - offsets.filter { $0 < destination }.count)
        for (index, id) in preferences.manualAccountOrder.enumerated() where !ids.contains(id) {
            result.insert(id, at: min(index, result.count))
        }
        preferences.manualAccountOrder = result
        save()
    }

    /// Coalesces concurrent requests and keeps last successful readings on failure.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; hasRefreshed = true }
        repeat {
            refreshAfterCurrent = false
            await readAccounts()
        } while refreshAfterCurrent && !Task.isCancelled
    }

    private func readAccounts() async {
        do {
            rawAccounts = try await provider.refresh()
            preferences = try provider.loadSettings(preferences)
            if preferences.accountOrderMode == .manual {
                let known = Set(preferences.manualAccountOrder)
                let discovered = rawAccounts.map(\.id).filter { !known.contains($0) }
                if !discovered.isEmpty {
                    preferences.manualAccountOrder += discovered
                    try persistPreferences()
                }
            }
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
        let wasEnabled = accounts.first { $0.id == id }?.isEnabled == true
        updateAccount(id) { $0.isEnabled = isEnabled }
        guard isEnabled, !wasEnabled, accounts.first(where: { $0.id == id })?.isEnabled == true else { return }
        refreshAfterCurrent = true
        Task { [weak self] in await self?.refresh() }
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

    private func persistPreferences() throws {
        let data = try JSONEncoder().encode(preferences)
        defaults.set(data, forKey: Self.preferencesKey)
        savedPreferences = preferences
    }

    private func save() {
        do {
            try provider.saveSettings(preferences, accounts: rawAccounts)
            preferences = try provider.loadSettings(preferences)
            try persistPreferences()
            settingsError = nil
        } catch {
            preferences = savedPreferences
            settingsError = "Could not save settings to ~/.config/leeway/policy.toml. Check that the file is writable and valid TOML."
        }
        applyPreferences()
    }
}
