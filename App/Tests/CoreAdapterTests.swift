import AppCore
import AppModel
import LeewayCore
import XCTest

final class CoreAdapterTests: XCTestCase {
    func testAdapter_MissingReading_RemainsUnknown() {
        let status = AccountStatus(id: "one", label: "Account 1", provider: .codex, configDir: "/fixture/codex")
        let result = CoreSnapshotMapper.map(StatusDocument(generatedAt: Date(), accounts: [status]))
        XCTAssertEqual(result.first?.id, "one")
        XCTAssertEqual(result.first?.folder, "/fixture/codex")
        XCTAssertNil(result.first?.weeklyUsed)
        XCTAssertNil(result.first?.reset)
        XCTAssertNil(result.first?.upperForecast)
        XCTAssertTrue(result.first?.isStale == true)
    }

    func testAdapter_SafeErrorsKeepReadingAndTimestamp() {
        for reason in AccountReadError.allCases {
            let date = Date(timeIntervalSince1970: 1800000000)
            let status = AccountStatus(id: "one", label: "One", provider: .claude, configDir: "/fixture",
                sevenDay: UsageWindow(pct: 42, resetsAt: date.addingTimeInterval(86400)),
                error: reason, asOf: date)
            let account = CoreSnapshotMapper.map(StatusDocument(generatedAt: date, accounts: [status]))[0]
            XCTAssertEqual(account.error, reason)
            XCTAssertEqual(account.weeklyUsed, 42)
            XCTAssertEqual(account.recordedAt, date)
        }
    }

    func testAdapter_MapsReadingsHistoryAndBothForecasts() {
        let now = Date(timeIntervalSince1970: 1800000000)
        let reset = now.addingTimeInterval(4 * 86400)
        let points = [HistoryPoint(at: now.addingTimeInterval(-86400), pct: 20), HistoryPoint(at: now, pct: 30)]
        let forecast = Forecaster.forecast(points, resetsAt: reset, now: now)
        let status = AccountStatus(id: "one", label: "Account 1", provider: .codex, configDir: "/fixture/codex",
                                   fiveHour: UsageWindow(pct: 10, resetsAt: now), sevenDay: UsageWindow(pct: 30, resetsAt: reset),
                                   forecast: forecast, stale: false, asOf: now, targetHigh: 80)
        let result = CoreSnapshotMapper.map(StatusDocument(generatedAt: now, accounts: [status], history: ["one": points]))[0]
        XCTAssertEqual(result.weeklyUsed, 30)
        XCTAssertEqual(result.fiveHourUsed, 10)
        XCTAssertEqual(result.weekForecast, 70)
        XCTAssertEqual(result.recentForecast, 70)
        XCTAssertEqual(result.history.count, 2)
        XCTAssertEqual(result.history.first?.used, 20)
        XCTAssertEqual(result.targetHigh, 80)
        XCTAssertFalse(result.isStale)
    }
}

@MainActor
final class CoreProviderTests: XCTestCase {
    func testRefresh_DisabledAccountsRemainAvailableInSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("policy.toml")
        try """
        [[accounts]]
        id = "disabled"
        provider = "codex"
        label = "Account 1"
        config_dir = "/fixture/codex"
        enabled = false
        """.write(to: url, atomically: true, encoding: .utf8)
        let provider = CoreUsageProvider(settings: PolicySettingsStore(url: url, home: directory)) { _ in EmptyCoreSource() }
        let result = try await provider.refresh()
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].isEnabled)
        XCTAssertEqual(result[0].name, "Account 1")
    }
}

private actor EmptyCoreSource: LeewayCore.UsageProvider {
    func status(refresh: Bool) async throws -> StatusDocument { StatusDocument(generatedAt: Date()) }
    func advise(_ request: AdviceRequest) async throws -> Advice { Advice(verdict: .go, reason: "fixture") }
}

@MainActor
final class CoreAliasTests: XCTestCase {
    func testRefresh_DeduplicatedAlias_DoesNotBecomeAnExtraMissingAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("policy.toml")
        try """
        [[accounts]]
        id = "alias"
        provider = "claude"
        config_dir = "/fixture/alias"
        """.write(to: url, atomically: true, encoding: .utf8)
        let provider = CoreUsageProvider(settings: PolicySettingsStore(url: url, home: directory)) { _ in AliasCoreSource() }
        let result = try await provider.refresh()
        XCTAssertEqual(result.map(\.id), ["canonical"])
    }
}

private actor AliasCoreSource: LeewayCore.UsageProvider {
    func status(refresh: Bool) async throws -> StatusDocument {
        StatusDocument(generatedAt: Date(), accounts: [AccountStatus(id: "canonical", label: "Account 1", provider: .claude,
            configDir: "/fixture/main", aliases: ["/fixture/alias"])])
    }
    func advise(_ request: AdviceRequest) async throws -> Advice { Advice(verdict: .go, reason: "fixture") }
}

@MainActor
final class LiveCoreTests: XCTestCase {
    func testLiveProvider_ReadsCodexFixture_AndSharesPersistedHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = directory.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let limits: [String: Any] = [
            "primary": ["used_percent": 10, "window_minutes": 300, "resets_at": now.addingTimeInterval(3600).timeIntervalSince1970],
            "secondary": ["used_percent": 30, "window_minutes": 10080, "resets_at": now.addingTimeInterval(4 * 86400).timeIntervalSince1970]
        ]
        let record: [String: Any] = ["timestamp": ISO8601DateFormatter().string(from: now), "type": "event_msg",
                                   "payload": ["type": "token_count", "rate_limits": limits]]
        try JSONSerialization.data(withJSONObject: record).write(to: sessions.appendingPathComponent("rollout-fixture.jsonl"))
        let first = try CoreUsageProvider.live(home: directory, environment: [:])
        let result = try await first.refresh()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.weeklyUsed, 30)
        XCTAssertEqual(result.first?.fiveHourUsed, 10)
        XCTAssertEqual(result.first?.history.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            directory.appendingPathComponent("Library/Application Support/leeway/history.sqlite").path))
        let second = try CoreUsageProvider.live(home: directory, environment: [:])
        let restored = try await second.refresh()
        XCTAssertEqual(restored.first?.history.first?.used, 30)
    }
}

@MainActor
final class AliasSettingsTests: XCTestCase {
    func testDisable_AllKnownDirectoriesAreDisabled_AfterProviderReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = PolicySettingsStore(url: directory.appendingPathComponent("policy.toml"), home: directory)
        let preferences = UserDefaults(suiteName: UUID().uuidString)!
        let provider = CoreUsageProvider(settings: settings) { _ in AliasCoreSource() }
        let model = UsageModel(provider: provider, defaults: preferences)
        await model.refresh()
        model.setEnabled(false, for: "canonical")
        let policy = try Policy.load(settings.url, home: directory)
        XCTAssertEqual(Set(policy.accounts.map { $0.configDir.path }), ["/fixture/main", "/fixture/alias"])
        XCTAssertTrue(policy.accounts.allSatisfy { !$0.isEnabled })
        let restarted = UsageModel(provider: CoreUsageProvider(settings: settings) { _ in EmptyCoreSource() }, defaults: preferences)
        await restarted.refresh()
        XCTAssertEqual(restarted.accounts.count, 1)
        XCTAssertTrue(restarted.enabledAccounts.isEmpty)
    }
}

final class DefaultAccountNameTests: XCTestCase {
    func testMapper_DefaultNameNeedsHint_AndExplicitRenameWins() {
        let status = AccountStatus(id: "work", label: "Claude (claude-work)", provider: .claude, configDir: "/fixture/.claude-work")
        var account = CoreSnapshotMapper.map(StatusDocument(generatedAt: Date(), accounts: [status]))[0]
        XCTAssertTrue(account.hasDefaultName)
        account.name = "Research"
        XCTAssertFalse(account.hasDefaultName)
        XCTAssertEqual(account.name, "Research")
    }
}

extension DefaultAccountNameTests {
    func testMapper_AlternateHomeStillRecognizesStandardDefaultName() {
        let home = URL(fileURLWithPath: "/fixture")
        let status = AccountStatus(id: "default", label: "Claude", provider: .claude, configDir: "/fixture/.claude")
        let value = CoreSnapshotMapper.map(StatusDocument(generatedAt: Date(), accounts: [status]), home: home)[0]
        XCTAssertTrue(value.hasDefaultName)
    }
}

final class AverageOnlyForecastTests: XCTestCase {
    func testAdapter_AverageOnlyForecast_PreservesRangeAndStatus() {
        let forecast = Forecast(averagePctAtReset: 84, recentPctAtReset: nil,
            rangeLow: 84, rangeHigh: 84, nextRoundPct: 14, exhaustsAt: nil, confidence: .low)
        let status = AccountStatus(id: "one", label: "One", provider: .codex, configDir: "/fixture",
            sevenDay: UsageWindow(pct: 13), forecast: forecast, stale: false)
        let account = CoreSnapshotMapper.map(StatusDocument(generatedAt: Date(), accounts: [status]))[0]
        XCTAssertNil(account.recentForecast)
        XCTAssertEqual(account.lowerForecast, 84)
        XCTAssertEqual(account.upperForecast, 84)
        XCTAssertEqual(account.status, .onTarget)
    }
}

extension AverageOnlyForecastTests {
    func testAdapter_NoProjectionButUsedAboveCeiling_MatchesCoreStatus() {
        let status = AccountStatus(id: "one", label: "One", provider: .codex, configDir: "/fixture",
            sevenDay: UsageWindow(pct: 60), forecast: .empty, stale: false, targetLow: 40, targetHigh: 50)
        let account = CoreSnapshotMapper.map(StatusDocument(generatedAt: Date(), accounts: [status]))[0]
        XCTAssertNil(account.upperForecast)
        XCTAssertEqual(account.status, .onTarget)
    }
}
