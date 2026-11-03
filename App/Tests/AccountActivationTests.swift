import AppCore
import AppModel
import LeewayCore
import XCTest
@testable import LeewayPresentation

@MainActor
final class AccountActivationTests: XCTestCase {
    func testEnable_RequestsFreshReadingWithoutWaitingForPollingInterval() async {
        let provider = ActivationProvider()
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        XCTAssertNil(model.accounts[0].weeklyUsed)
        model.setEnabled(true, for: "work")
        // Yield to the model's asynchronous refresh without a wall-clock sleep.
        for _ in 0..<100 where model.accounts[0].weeklyUsed == nil { await Task.yield() }
        XCTAssertEqual(model.accounts[0].weeklyUsed, 30)
        XCTAssertEqual(provider.requests, 2)
    }

    func testEnable_FailedReadingShowsTypedReasonInMenu() async {
        let provider = ActivationProvider()
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        provider.readError = .timeout
        model.setEnabled(true, for: "work")
        for _ in 0..<100 where model.accounts[0].error == nil { await Task.yield() }
        XCTAssertEqual(model.accounts[0].error, .timeout)
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/en.lproj")
        let strings = Localizer(language: .english, resourceBundle: Bundle(path: resources.path)!)
        XCTAssertEqual(strings.menuCaption(model.accounts[0]), "Reading timed out")
    }

    func testEnable_DuringRefreshRequestsAnotherReadingAfterCurrentOne() async {
        let provider = ActivationProvider()
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        provider.shouldSuspend = true
        let inFlight = Task { await model.refresh() }
        while provider.requests < 2 { await Task.yield() }
        model.setEnabled(true, for: "work")
        provider.resume()
        await inFlight.value
        XCTAssertEqual(model.accounts[0].weeklyUsed, 30)
        XCTAssertEqual(provider.requests, 3)
    }

    func testEnable_FailedSaveDoesNotRequestReading() async {
        let provider = ActivationProvider()
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        provider.failsSave = true
        model.setEnabled(true, for: "work")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(provider.requests, 1)
        XCTAssertFalse(model.accounts[0].isEnabled)
    }
}

@MainActor
private final class ActivationProvider: AppModel.UsageProvider {
    var requests = 0
    var failsSave = false
    var readError: AccountReadError?
    var shouldSuspend = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var isEnabled = false

    func refresh() async throws -> [AccountUsage] {
        requests += 1
        var value = AccountUsage(id: "work", name: "Work", source: "Codex", weeklyUsed: isEnabled && readError == nil ? 30 : nil,
            fiveHourUsed: nil, reset: nil, fiveHourReset: nil, weekForecast: nil, recentForecast: nil,
            recordedAt: nil, history: [])
        value.isEnabled = isEnabled
        value.error = readError
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { continuation = $0 }
        }
        return [value]
    }

    func resume() { continuation?.resume(); continuation = nil }

    func loadSettings(_ stored: AppPreferences) throws -> AppPreferences {
        var result = stored
        result.accounts["work"] = AccountPreference(isEnabled: isEnabled)
        return result
    }

    func saveSettings(_ preferences: AppPreferences, accounts: [AccountUsage]) throws {
        if failsSave { throw CocoaError(.fileWriteNoPermission) }
        isEnabled = preferences.accounts["work"]?.isEnabled ?? false
    }
}
