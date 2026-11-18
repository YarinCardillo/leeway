import AppCore
import AppModel
import Foundation
import LeewayCore
import XCTest

private final class CountingRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var week: Double
    init(week: Double = 0.5) { self.week = week }
    var calls: Int { lock.withLock { count } }
    func setWeek(_ value: Double) { lock.withLock { week = value } }

    func run(_ request: ProcessRequest) throws -> ProcessOutput {
        lock.withLock { count += 1 }
        if request.arguments.first == "auth" { return ProcessOutput(exitCode: 0, stdout: "{\"loggedIn\":true}") }
        let reset = Date().addingTimeInterval(86400 * 3).timeIntervalSince1970
        let fiveReset = Date().addingTimeInterval(3600).timeIntervalSince1970
        let used = lock.withLock { week }
        return ProcessOutput(exitCode: 0, stdout: """
            {"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.1,"resetsAt":\(fiveReset)},"seven_day":{"utilization":\(used),"resetsAt":\(reset)}}}}
            """)
    }
}

private actor ServedElsewhereSource: LeewayCore.UsageProvider {
    func status(refresh: Bool) async throws -> StatusDocument { StatusDocument(generatedAt: Date()) }
    func advise(_ request: AdviceRequest) async throws -> Advice { Advice(verdict: .go, reason: "fixture") }
    func servePendingRefresh() async -> Bool { true }
}

@MainActor
final class PollingCoordinationTests: XCTestCase {
    private var home: URL!
    private var databasePath: String { home.appendingPathComponent("history.sqlite").path }
    private var lockPath: String { home.appendingPathComponent("poll.lock").path }
    private var model: UsageModel?

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("leeway-poll-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        model?.stopPolling()
        try? FileManager.default.removeItem(at: home)
    }

    private func service(_ runner: CountingRunner, store: SnapshotStore? = nil) throws -> UsageService {
        UsageService(home: home, policy: Policy(), store: try store ?? SnapshotStore(path: databasePath), runner: runner,
            environment: [:], pollLock: PollLock(path: lockPath))
    }

    private func appProvider(_ service: UsageService, store: SnapshotStore) -> CoreUsageProvider {
        CoreUsageProvider(settings: PolicySettingsStore(url: home.appendingPathComponent("policy.toml"), home: home),
            store: store) { _ in service }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }

    func testBackgroundWork_AppHoldingThePollLock_ServesARefreshAnotherProcessQueued() async throws {
        let appStore = try SnapshotStore(path: databasePath)
        let appRunner = CountingRunner()
        let provider = appProvider(try service(appRunner, store: appStore), store: appStore)
        _ = try await provider.refresh()
        _ = try await service(CountingRunner()).status(refresh: true)
        XCTAssertTrue(try appStore.hasRefreshRequest())
        let callsBefore = appRunner.calls
        await provider.serveBackgroundWork()
        XCTAssertGreaterThan(appRunner.calls, callsBefore)
        XCTAssertFalse(try appStore.hasRefreshRequest())
    }

    func testScheduledRefresh_AppThatDoesNotPoll_ReadsTheStoreAndQueuesNothing() async throws {
        let holder = try service(CountingRunner(week: 0.5))
        _ = try await holder.status(refresh: true)
        let appStore = try SnapshotStore(path: databasePath)
        let appRunner = CountingRunner()
        let provider = appProvider(try service(appRunner, store: appStore), store: appStore)
        let rows = try await provider.scheduledRefresh()
        XCTAssertEqual(rows.first?.weeklyUsed, 50)
        XCTAssertEqual(appRunner.calls, 0)
        XCTAssertFalse(try appStore.hasRefreshRequest())
    }

    func testPollingModel_FirstRoundOnAFollower_QueuesNoRequest() async throws {
        let holder = try service(CountingRunner())
        _ = try await holder.status(refresh: true)
        defer { withExtendedLifetime(holder) {} }
        let appStore = try SnapshotStore(path: databasePath)
        let appRunner = CountingRunner()
        let model = UsageModel(provider: appProvider(try service(appRunner, store: appStore), store: appStore),
            defaults: UserDefaults(suiteName: UUID().uuidString)!)
        self.model = model
        model.startPolling()
        try await waitUntil { model.hasRefreshed }
        XCTAssertEqual(appRunner.calls, 0)
        XCTAssertFalse(try appStore.hasRefreshRequest())
        await model.refresh()
        XCTAssertTrue(try appStore.hasRefreshRequest())
    }

    func testFollowerApp_ShowsTheReadingThePollerStoresAfterItsRequest() async throws {
        let holderRunner = CountingRunner(week: 0.5)
        let holder = try service(holderRunner)
        _ = try await holder.status(refresh: true)
        let appStore = try SnapshotStore(path: databasePath)
        let provider = appProvider(try service(CountingRunner(), store: appStore), store: appStore)
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        self.model = model
        model.startPolling()
        try await waitUntil { model.hasRefreshed }
        await model.refresh()
        XCTAssertEqual(model.accounts.first?.weeklyUsed, 50)
        holderRunner.setWeek(0.6)
        await holder.servePendingRefresh()
        await provider.serveBackgroundWork()
        try await waitUntil { model.accounts.first?.weeklyUsed == 60 }
    }

    func testBackgroundWork_ServingARequestAsThePoller_TellsTheModelToReload() async throws {
        let appStore = try SnapshotStore(path: databasePath)
        let appRunner = CountingRunner(week: 0.3)
        let provider = appProvider(try service(appRunner, store: appStore), store: appStore)
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        self.model = model
        model.startPolling()
        try await waitUntil { model.hasRefreshed }
        appRunner.setWeek(0.8)
        let other = try service(CountingRunner())
        _ = try await other.status(refresh: true)
        await provider.serveBackgroundWork()
        try await waitUntil { model.accounts.first?.weeklyUsed == 80 }
    }

    func testBackgroundWork_ARefreshTheSourceServed_TellsTheObserverWithoutRelyingOnAnEarlierLook() async throws {
        let appStore = try SnapshotStore(path: databasePath)
        let provider = CoreUsageProvider(settings: PolicySettingsStore(url: home.appendingPathComponent("policy.toml"), home: home),
            store: appStore) { _ in ServedElsewhereSource() }
        var changes = 0
        provider.observeStoreChanges { changes += 1 }
        XCTAssertFalse(try appStore.hasRefreshRequest())
        await provider.serveBackgroundWork()
        XCTAssertEqual(changes, 1)
    }

    func testBackgroundWork_PolicyFileBecomesInvalid_KeepsServingWithTheLastValidPolicy() async throws {
        let appStore = try SnapshotStore(path: databasePath)
        let appRunner = CountingRunner()
        let provider = appProvider(try service(appRunner, store: appStore), store: appStore)
        _ = try await provider.refresh()
        try Data("[[accounts\nnot toml".utf8).write(to: home.appendingPathComponent("policy.toml"))
        _ = try await service(CountingRunner()).status(refresh: true)
        XCTAssertTrue(try appStore.hasRefreshRequest())
        let callsBefore = appRunner.calls
        await provider.serveBackgroundWork()
        XCTAssertGreaterThan(appRunner.calls, callsBefore)
        XCTAssertFalse(try appStore.hasRefreshRequest())
    }

    func testScheduledRefresh_PolicyFileBecomesInvalid_StillPollsWithTheLastValidPolicy() async throws {
        let appStore = try SnapshotStore(path: databasePath)
        let appRunner = CountingRunner()
        let provider = appProvider(try service(appRunner, store: appStore), store: appStore)
        _ = try await provider.refresh()
        try Data("[[accounts\nnot toml".utf8).write(to: home.appendingPathComponent("policy.toml"))
        let callsBefore = appRunner.calls
        _ = try await provider.scheduledRefresh()
        XCTAssertGreaterThan(appRunner.calls, callsBefore)
    }

    func testBackgroundWork_AccountBookReplacedByAnotherProcess_TellsTheObserver() async throws {
        let appStore = try SnapshotStore(path: databasePath)
        let provider = appProvider(try service(CountingRunner(), store: appStore), store: appStore)
        var changes = 0
        provider.observeStoreChanges { changes += 1 }
        await provider.serveBackgroundWork()
        XCTAssertEqual(changes, 0)
        let command = AccountsCommand(home: home, policy: Policy(), environment: [:])
        try command.edit { try $0.hide(id: "claude-default") }
        await provider.serveBackgroundWork()
        XCTAssertEqual(changes, 1)
        await provider.serveBackgroundWork()
        XCTAssertEqual(changes, 1)
    }
}
