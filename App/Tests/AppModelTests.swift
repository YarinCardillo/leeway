import XCTest
@testable import AppModel

@MainActor
final class AppModelTests: XCTestCase {
    func testRefresh_FirstOrderedEnabledAccountIsSelected() async {
        let model = makeModel()
        await model.refresh()
        XCTAssertEqual(model.selectedAccount?.id, "high")
        model.setAccountOrderMode(.manual)
        model.moveAccounts(fromOffsets: [1], toOffset: 0)
        XCTAssertEqual(model.selectedAccount?.id, "low")
        model.setEnabled(false, for: "low")
        XCTAssertEqual(model.selectedAccount?.id, "high")
    }

    func testRefresh_FailureRetainsLastReading_AndMarksItStale() async {
        let provider = TestProvider()
        let model = makeModel(provider: provider)
        await model.refresh()
        provider.shouldFail = true
        await model.refresh()
        XCTAssertEqual(model.accounts.count, 2)
        XCTAssertEqual(model.accounts.first?.weeklyUsed, 30)
        XCTAssertTrue(model.accounts.allSatisfy(\.isStale))
        XCTAssertNotNil(model.refreshError)
        provider.shouldFail = false
        await model.refresh()
        XCTAssertNil(model.refreshError)
        XCTAssertFalse(model.accounts.contains(where: \.isStale))
    }

    func testPreferences_RenameCeilingReserveAndLanguage_SurviveRefreshAndReload() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = makeModel(defaults: defaults)
        await model.refresh()
        model.rename("Personal", for: "low")
        model.setTarget(low: 40, high: 50, for: "low")
        model.setReserve("high", for: "low")
        model.setPollingMinutes(5)
        model.setLanguage(.italian)
        await model.refresh()
        let restored = makeModel(defaults: defaults)
        await restored.refresh()
        XCTAssertEqual(restored.accounts.first?.name, "Personal")
        XCTAssertEqual(restored.accounts.first?.targetHigh, 50)
        XCTAssertEqual(restored.preferences.accounts["low"]?.reserveID, "high")
        XCTAssertEqual(restored.preferences.pollingMinutes, 5)
        XCTAssertEqual(restored.preferences.language, .italian)
        XCTAssertEqual(restored.accounts.first?.status, .over)
    }

    func testPreferences_InvalidValues_AreRejected() async {
        let model = makeModel()
        await model.refresh()
        model.rename("  ", for: "low")
        model.setTarget(low: 75, high: 49, for: "low")
        model.setPollingMinutes(1)
        model.setReserve("low", for: "low")
        XCTAssertEqual(model.accounts.first?.name, "Low")
        XCTAssertEqual(model.accounts.first?.targetHigh, 100)
        XCTAssertEqual(model.preferences.pollingMinutes, 15)
        XCTAssertNil(model.preferences.accounts["low"]?.reserveID)
    }

    func testAccount_UsedAt95WithinForecastRange_IsOnTarget() {
        var account = TestProvider.readings[0]
        account.weeklyUsed = 95
        XCTAssertEqual(account.status, .onTarget)
    }

    private func makeModel(
        provider: TestProvider = TestProvider(), defaults: UserDefaults? = nil
    ) -> UsageModel {
        UsageModel(provider: provider, defaults: defaults ?? UserDefaults(suiteName: UUID().uuidString)!)
    }
}

@MainActor
final class TestProvider: UsageProvider {
    var shouldFail = false
    static var readings: [AccountUsage] {
        [
            AccountUsage(id: "low", name: "Low", source: "Codex", weeklyUsed: 30,
                         fiveHourUsed: 10, reset: Date().addingTimeInterval(86400),
                         fiveHourReset: nil, weekForecast: 60, recentForecast: 70,
                         recordedAt: Date(), history: []),
            AccountUsage(id: "high", name: "High", source: "Claude Code", weeklyUsed: 70,
                         fiveHourUsed: 20, reset: Date().addingTimeInterval(86400),
                         fiveHourReset: nil, weekForecast: 110, recentForecast: 120,
                         recordedAt: Date(), history: [])
        ]
    }

    func refresh() async throws -> [AccountUsage] {
        if shouldFail { throw CocoaError(.fileReadUnknown) }
        return Self.readings
    }
}

@MainActor
final class MissingUsageTests: XCTestCase {
    func testUnknownUsage_FirstAccountStillOwnsTheStatusItem() async {
        let model = UsageModel(provider: MissingProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        XCTAssertEqual(model.selectedAccount?.id, "unknown")
        XCTAssertNil(model.accounts.first?.upperForecast)
        XCTAssertNil(model.accounts.first?.lowerForecast)
    }
}

@MainActor
private struct MissingProvider: UsageProvider {
    func refresh() async throws -> [AccountUsage] {
        [AccountUsage(id: "unknown", name: "Account 1", source: "Codex", weeklyUsed: nil,
                      fiveHourUsed: nil, reset: nil, fiveHourReset: nil,
                      weekForecast: nil, recentForecast: nil, recordedAt: nil, history: [])]
    }
}

@MainActor
final class RefreshCoordinationTests: XCTestCase {
    func testRefresh_ConcurrentRequest_IsCoalesced() async {
        let provider = SuspendedProvider()
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let first = Task { await model.refresh() }
        while !provider.hasStarted { await Task.yield() }
        await model.refresh()
        XCTAssertTrue(model.isRefreshing)
        XCTAssertEqual(provider.requests, 1)
        provider.finish()
        await first.value
        XCTAssertFalse(model.isRefreshing)
    }
}

@MainActor
private final class SuspendedProvider: UsageProvider {
    var hasStarted = false
    var requests = 0
    private var continuation: CheckedContinuation<[AccountUsage], Never>?

    func refresh() async throws -> [AccountUsage] {
        requests += 1
        hasStarted = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish() { continuation?.resume(returning: []); continuation = nil }
}

final class CompactMenuBarTests: XCTestCase {
    func testPreferences_OlderSavedSettingsDefaultToCompact() throws {
        let old = """
        {"accounts":{},"pollingMinutes":15,"language":"system","updatesAutomatically":true,"updateChannel":"stable","addedFolders":[],"folderProviders":{}}
        """
        XCTAssertTrue(try JSONDecoder().decode(AppPreferences.self, from: Data(old.utf8)).isMenuBarCompact)
    }
}

extension AppModelTests {
    func testTarget_WholeRangeCanReachBounds() async {
        let model = makeModel()
        await model.refresh()
        model.setTarget(low: 0, high: 5, for: "low")
        XCTAssertEqual(model.accounts.first?.targetLow, 0)
        XCTAssertEqual(model.accounts.first?.targetHigh, 5)
        model.setTarget(low: 95, high: 100, for: "low")
        XCTAssertEqual(model.accounts.first?.targetLow, 95)
        XCTAssertEqual(model.accounts.first?.targetHigh, 100)
    }
}

extension AppModelTests {
    func testCompactPreference_PercentagesChoiceSurvivesReload() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = makeModel(defaults: defaults)
        model.setMenuBarCompact(false)
        let restored = makeModel(defaults: defaults)
        XCTAssertFalse(restored.preferences.isMenuBarCompact)
    }
}
