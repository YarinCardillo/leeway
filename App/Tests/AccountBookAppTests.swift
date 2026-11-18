import AppCore
import AppModel
import Foundation
import LeewayCore
import XCTest

private struct NoProcessRunner: ProcessRunner {
    func run(_ request: ProcessRequest) throws -> ProcessOutput { throw CoreError.process }
}

@MainActor
final class AccountBookAppTests: XCTestCase {
    private var home: URL!

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("leeway-app-" + UUID().uuidString)
        for name in [".codex", "extra"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true)
        }
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: home) }

    private var policyFile: URL { home.appendingPathComponent(".config/leeway/policy.toml") }

    private func makeProvider() -> CoreUsageProvider {
        let home = home!
        return CoreUsageProvider(settings: PolicySettingsStore(url: policyFile, home: home)) { policy in
            UsageService(home: home, policy: policy, store: try SnapshotStore(path: ":memory:"),
                runner: NoProcessRunner(), environment: [:])
        }
    }

    private func book() throws -> AccountBook { try AccountBook.load(AccountBook.fileURL(home: home)) }

    func testRemoveAccount_AutoDiscoveredAccountStaysGone_AndAddingItsFolderBringsItBack() async throws {
        let provider = makeProvider()
        let first = try await provider.refresh()
        XCTAssertEqual(first.map(\.id), ["codex-default"])
        try provider.removeAccount(first[0])
        let removed = try await provider.refresh()
        XCTAssertTrue(removed.isEmpty)
        try provider.addFolder(home.appendingPathComponent(".codex").path, provider: "codex")
        let restored = try await provider.refresh()
        XCTAssertEqual(restored.count, 1)
    }

    func testRefresh_FolderThatDisappeared_IsListedAsMissingAndCanBeRemoved() async throws {
        let provider = makeProvider()
        _ = try await provider.refresh()
        try FileManager.default.removeItem(at: home.appendingPathComponent(".codex"))
        let rows = try await provider.refresh()
        XCTAssertEqual(rows.map(\.id), ["codex-default"])
        XCTAssertTrue(rows[0].isFolderMissing)
        XCTAssertTrue(rows[0].isStale)
        try provider.removeAccount(rows[0])
        let after = try await provider.refresh()
        XCTAssertTrue(after.isEmpty)
    }

    func testRemoveAccount_PolicyAccountWithMissingFolder_IsRemovedAndPrunedFromPolicyAlone() async throws {
        try FileManager.default.createDirectory(at: policyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        [[accounts]]
        id = "old"
        provider = "claude"
        config_dir = "/fixture/gone"
        """.write(to: policyFile, atomically: true, encoding: .utf8)
        let model = UsageModel(provider: makeProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let old = try XCTUnwrap(model.accounts.first { $0.id == "old" })
        XCTAssertTrue(old.isFolderMissing)
        model.removeAccount(old)
        XCTAssertNil(model.accounts.first { $0.id == "old" })
        await model.refresh()
        XCTAssertNil(model.accounts.first { $0.id == "old" })
        XCTAssertNil(model.settingsError)
        XCTAssertFalse(try Policy.load(policyFile, home: home).accounts.contains { $0.id == "old" })
    }

    func testLoadSettings_OldPreferencesMoveIntoTheBookOnceAndAreNotReadAgain() throws {
        let provider = makeProvider()
        var stored = AppPreferences()
        stored.addedFolders = [home.appendingPathComponent("extra").path]
        stored.folderProviders = [stored.addedFolders[0]: "codex"]
        stored.accountOrderMode = .manual
        stored.manualAccountOrder = ["codex-default"]
        let loaded = try provider.loadSettings(stored)
        let saved = try book()
        XCTAssertTrue(saved.appPreferencesImported)
        XCTAssertEqual(saved.accounts.filter { $0.origin == .added }.map(\.provider), [.codex])
        XCTAssertEqual(loaded.manualAccountOrder, saved.ordered.map(\.id))
        XCTAssertTrue(loaded.addedFolders.isEmpty)
        stored.addedFolders = [home.path]
        stored.manualAccountOrder = ["x"]
        let again = try makeProvider().loadSettings(stored)
        XCTAssertEqual(try book(), saved)
        XCTAssertEqual(again.manualAccountOrder, loaded.manualAccountOrder)
    }

    func testSaveSettings_ManualOrderChangesLandInTheBookAndSurviveAReload() async throws {
        let provider = makeProvider()
        var preferences = try provider.loadSettings(AppPreferences())
        _ = try await provider.refresh()
        preferences = try provider.loadSettings(preferences)
        XCTAssertEqual(preferences.manualAccountOrder.first, "codex-default")
        try provider.addFolder(home.appendingPathComponent("extra").path, provider: "codex")
        preferences = try provider.loadSettings(preferences)
        let extraID = try XCTUnwrap(preferences.manualAccountOrder.first { $0 != "codex-default" })
        preferences.manualAccountOrder = [extraID, "codex-default"]
        try provider.saveSettings(preferences, accounts: [])
        let reloaded = try makeProvider().loadSettings(AppPreferences())
        XCTAssertEqual(reloaded.manualAccountOrder, [extraID, "codex-default"])
    }

    func testModelRemoveAccount_DropsTheRowAndItsSavedOrderWithAnyProvider() async {
        let model = UsageModel(provider: TestProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        model.setAccountOrderMode(.manual)
        model.removeAccount(model.accounts[0])
        XCTAssertEqual(model.accounts.map(\.id), ["high"])
        XCTAssertEqual(model.preferences.manualAccountOrder, ["high"])
    }
}
