import AppCore
import AppModel
import Foundation
import LeewayCore
import XCTest

private struct NoProcessRunner: ProcessRunner {
    func run(_ request: ProcessRequest) throws -> ProcessOutput { throw CoreError.process }
}

/// The account book is the only authority for names: the policy label only seeds it.
@MainActor
final class AccountNamingTests: XCTestCase {
    private var home: URL!

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("leeway-names-" + UUID().uuidString)
        for name in [".codex", "extra"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: policyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        [[accounts]]
        id = "work"
        provider = "codex"
        label = "Work"
        config_dir = "\(home.appendingPathComponent("extra").path)"
        """.write(to: policyFile, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: home) }

    private var policyFile: URL { home.appendingPathComponent(".config/leeway/policy.toml") }

    private func makeModel() -> UsageModel {
        let home = home!
        let provider = CoreUsageProvider(settings: PolicySettingsStore(url: policyFile, home: home)) { policy in
            UsageService(home: home, policy: policy, store: try SnapshotStore(path: ":memory:"),
                runner: NoProcessRunner(), environment: [:])
        }
        return UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func command() throws -> AccountsCommand {
        AccountsCommand(home: home, policy: try Policy.load(policyFile, home: home), environment: [:])
    }

    private func bookLabel(_ id: String) throws -> String? {
        try AccountBook.load(AccountBook.fileURL(home: home)).accounts.first { $0.id == id }?.label
    }

    func testRefresh_ACommandLineRename_ReplacesTheNameTheAppLoadedFromPolicy() async throws {
        let model = makeModel()
        await model.refresh()
        XCTAssertEqual(model.accounts.first { $0.id == "work" }?.name, "Work")
        _ = try command().run(["rename", "work", "Office"])
        await model.refresh()
        XCTAssertEqual(model.accounts.first { $0.id == "work" }?.name, "Office")
    }

    func testRename_InTheApp_WritesTheBookAndLeavesThePolicyLabelAlone() async throws {
        let model = makeModel()
        await model.refresh()
        model.rename("Office", for: "work")
        XCTAssertNil(model.settingsError)
        XCTAssertEqual(model.accounts.first { $0.id == "work" }?.name, "Office")
        XCTAssertEqual(try bookLabel("work"), "Office")
        XCTAssertEqual(try Policy.load(policyFile, home: home).accounts.first?.label, "Work")
        let list = try command().run(["list"])
        XCTAssertTrue(list.contains("Office (work)"), list)
        let restarted = makeModel()
        await restarted.refresh()
        XCTAssertEqual(restarted.accounts.first { $0.id == "work" }?.name, "Office")
    }

    func testRename_OfADiscoveredAccount_ShowsAtOnceAndNeverEntersThePolicy() async throws {
        let model = makeModel()
        await model.refresh()
        model.rename("Side", for: "codex-default")
        XCTAssertEqual(model.accounts.first { $0.id == "codex-default" }?.name, "Side")
        XCTAssertEqual(try bookLabel("codex-default"), "Side")
        XCTAssertEqual(try Policy.load(policyFile, home: home).accounts.map(\.id), ["work"])
    }

    func testSettingsEdit_ThatIsNotARename_NeverFreezesTheDefaultNameIntoTheBook() async throws {
        let model = makeModel()
        await model.refresh()
        model.setTarget(low: 50, high: 90, for: "codex-default")
        XCTAssertNil(model.settingsError)
        XCTAssertNil(try bookLabel("codex-default"))
        XCTAssertEqual(try Policy.load(policyFile, home: home).accounts.first { $0.id == "codex-default" }?.targetLow, 50)
    }
}
