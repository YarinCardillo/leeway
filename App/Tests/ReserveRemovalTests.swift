import AppCore
import AppModel
import Foundation
import LeewayCore
import XCTest

private struct NoProcessRunner: ProcessRunner {
    func run(_ request: ProcessRequest) throws -> ProcessOutput { throw CoreError.process }
}

@MainActor
final class ReserveRemovalTests: XCTestCase {
    private var home: URL!
    private var policyFile: URL { home.appendingPathComponent(".config/leeway/policy.toml") }

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("leeway-reserve-" + UUID().uuidString)
        for name in ["first", "second"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: policyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        [[accounts]]
        id = "a"
        provider = "codex"
        config_dir = "\(home.appendingPathComponent("first").path)"
        reserve_account = "b"
        [[accounts]]
        id = "b"
        provider = "codex"
        config_dir = "\(home.appendingPathComponent("second").path)"
        """.write(to: policyFile, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: home) }

    private func makeModel() -> UsageModel {
        let home = home!
        let provider = CoreUsageProvider(settings: PolicySettingsStore(url: policyFile, home: home)) { policy in
            UsageService(home: home, policy: policy, store: try SnapshotStore(path: ":memory:"),
                runner: NoProcessRunner(), environment: [:])
        }
        return UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testRemoveAccount_ThatAnotherAccountUsesAsReserve_ClearsTheReserveAndKeepsSettingsSavable() async throws {
        let model = makeModel()
        await model.refresh()
        let reserve = try XCTUnwrap(model.accounts.first { $0.id == "b" })
        model.removeAccount(reserve)
        XCTAssertNil(model.settingsError)
        let policy = try Policy.load(policyFile, home: home)
        XCTAssertEqual(policy.accounts.map(\.id), ["a"])
        XCTAssertNil(policy.accounts.first?.reserveAccount)
        model.setTarget(low: 50, high: 90, for: "a")
        XCTAssertNil(model.settingsError)
        let saved = try Policy.load(policyFile, home: home)
        XCTAssertEqual(saved.accounts.first?.targetLow, 50)
        XCTAssertNil(saved.accounts.first?.reserveAccount)
    }
}
