import AppModel
import XCTest

@MainActor
final class AccountOrderingTests: XCTestCase {
    func testManualMove_PersistsAndSelectsTheFirstMenuAccount() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = UsageModel(provider: TestProvider(), defaults: defaults)
        await model.refresh()
        XCTAssertEqual(model.enabledAccounts.map(\.id), ["high", "low"])
        model.setAccountOrderMode(.manual)
        model.moveAccounts(fromOffsets: [1], toOffset: 0)
        XCTAssertEqual(model.enabledAccounts.map(\.id), ["low", "high"])
        XCTAssertEqual(model.selectedAccount?.id, "low")
        await model.refresh()
        XCTAssertEqual(model.enabledAccounts.map(\.id), ["low", "high"])
        let restored = UsageModel(provider: TestProvider(), defaults: defaults)
        await restored.refresh()
        XCTAssertEqual(restored.preferences.accountOrderMode, .manual)
        XCTAssertEqual(restored.enabledAccounts.map(\.id), ["low", "high"])
        restored.setAccountOrderMode(.mostAtRisk)
        XCTAssertEqual(restored.enabledAccounts.map(\.id), ["high", "low"])
        restored.setAccountOrderMode(.manual)
        XCTAssertEqual(restored.enabledAccounts.map(\.id), ["low", "high"])
    }

    func testManualOrder_MissingAndNewAccountsDoNotLoseSavedPositions() async {
        let provider = OrderingProvider()
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        model.setAccountOrderMode(.manual)
        model.moveAccounts(fromOffsets: [1], toOffset: 0)
        provider.values = [TestProvider.readings[1]]
        await model.refresh()
        XCTAssertEqual(model.orderedAccounts.map(\.id), ["high"])
        var new = AccountUsage(id: "new", name: "New", source: "Codex", weeklyUsed: 10, fiveHourUsed: nil,
            reset: nil, fiveHourReset: nil, weekForecast: 10, recentForecast: nil, recordedAt: nil, history: [])
        new.isEnabled = false
        provider.values = TestProvider.readings + [new]
        await model.refresh()
        XCTAssertEqual(model.orderedAccounts.map(\.id), ["low", "high", "new"])
        XCTAssertEqual(model.enabledAccounts.map(\.id), ["low", "high"])
    }

    func testManualMove_FailedSaveRestoresOrderAndMode() async {
        let provider = OrderingProvider()
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        model.setAccountOrderMode(.manual)
        provider.failsSave = true
        model.moveAccounts(fromOffsets: [1], toOffset: 0)
        XCTAssertEqual(model.enabledAccounts.map(\.id), ["high", "low"])
        XCTAssertNotNil(model.settingsError)
        model.setAccountOrderMode(.mostAtRisk)
        XCTAssertEqual(model.preferences.accountOrderMode, .manual)
    }

    func testManualMove_MultipleRowsUseNativeDestinationOffsets() async {
        let provider = OrderingProvider()
        provider.values += [AccountUsage(id: "third", name: "Third", source: "Codex", weeklyUsed: 0,
            fiveHourUsed: nil, reset: nil, fiveHourReset: nil, weekForecast: nil, recentForecast: nil, recordedAt: nil, history: [])]
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        model.setAccountOrderMode(.manual)
        model.moveAccounts(fromOffsets: [0, 1], toOffset: 3)
        XCTAssertEqual(model.orderedAccounts.map(\.id), ["third", "high", "low"])
        model.setAccountOrderMode(.mostAtRisk)
        let automatic = model.orderedAccounts.map(\.id)
        model.moveAccounts(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(model.orderedAccounts.map(\.id), automatic)
    }

    func testOlderPreferences_DefaultToMostAtRiskOrder() throws {
        let data = Data("""
        {"accounts":{},"pollingMinutes":15,"language":"system","updatesAutomatically":true,"addedFolders":[],"folderProviders":{}}
        """.utf8)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(preferences.accountOrderMode, .mostAtRisk)
        XCTAssertTrue(preferences.manualAccountOrder.isEmpty)
    }
}

@MainActor
private final class OrderingProvider: UsageProvider {
    var values = TestProvider.readings
    var failsSave = false
    func refresh() async throws -> [AccountUsage] { values }
    func saveSettings(_ preferences: AppPreferences, accounts: [AccountUsage]) throws {
        if failsSave { throw CocoaError(.fileWriteNoPermission) }
    }
}

extension AccountOrderingTests {
    func testManualMove_TemporarilyAbsentAccountKeepsItsSavedSlot() async {
        let provider = OrderingProvider()
        let third = AccountUsage(id: "third", name: "Third", source: "Codex", weeklyUsed: 0, fiveHourUsed: nil,
            reset: nil, fiveHourReset: nil, weekForecast: nil, recentForecast: nil, recordedAt: nil, history: [])
        provider.values += [third]
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        model.setAccountOrderMode(.manual)
        provider.values = [TestProvider.readings[1], third]
        await model.refresh()
        model.moveAccounts(fromOffsets: [1], toOffset: 0)
        provider.values = TestProvider.readings + [third]
        await model.refresh()
        XCTAssertEqual(model.orderedAccounts.map(\.id), ["third", "low", "high"])
    }
}

extension AccountOrderingTests {
    func testManualOrder_SuccessiveDiscoveriesAppendAndSurviveRelaunch() async {
        let provider = OrderingProvider()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = UsageModel(provider: provider, defaults: defaults)
        await model.refresh()
        model.setAccountOrderMode(.manual)
        func account(_ id: String, _ name: String) -> AccountUsage {
            AccountUsage(id: id, name: name, source: "Codex", weeklyUsed: 0, fiveHourUsed: nil,
                reset: nil, fiveHourReset: nil, weekForecast: nil, recentForecast: nil, recordedAt: nil, history: [])
        }
        provider.values += [account("new-first", "Zulu")]
        await model.refresh()
        provider.values += [account("new-second", "Alpha")]
        await model.refresh()
        XCTAssertEqual(model.orderedAccounts.map(\.id), ["high", "low", "new-first", "new-second"])
        let restored = UsageModel(provider: provider, defaults: defaults)
        await restored.refresh()
        XCTAssertEqual(restored.orderedAccounts.map(\.id), ["high", "low", "new-first", "new-second"])
    }
}
