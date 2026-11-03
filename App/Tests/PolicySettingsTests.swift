import AppCore
import AppModel
import Foundation
import LeewayCore
import XCTest

final class PolicySettingsTests: XCTestCase {
    func testSave_AccountChangesReachSharedPolicy_WithoutLosingRouting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("policy.toml")
        try """
        port = 8800
        [roles]
        reviewer = "sonnet"
        [[projects]]
        name = "Example"
        paths = ["/fixture/project"]
        codex = ["one"]
        [[accounts]]
        id = "one"
        provider = "codex"
        config_dir = "/fixture/codex"
        target_low = 40
        over_target = "warn"
        """.write(to: url, atomically: true, encoding: .utf8)
        let store = PolicySettingsStore(url: url, home: directory)
        var choices = try store.load(into: AppPreferences())
        choices.accounts["one"] = AccountPreference(name: "Personal", isEnabled: false, targetLow: 50, targetHigh: 60)
        choices.pollingMinutes = 5
        try store.save(choices, accounts: [])
        let policy = try Policy.load(url, home: directory)
        XCTAssertEqual(policy.port, 8800)
        XCTAssertEqual(policy.roles[.reviewer], "sonnet")
        XCTAssertEqual(policy.projects.first?.allowed.codex, ["one"])
        XCTAssertEqual(policy.accounts.first?.label, "Personal")
        XCTAssertEqual(policy.accounts.first?.targetHigh, 60)
        XCTAssertFalse(policy.accounts.first!.isEnabled)
        XCTAssertEqual(policy.accounts.first?.overTarget, .warn)
        XCTAssertEqual(policy.pollMinutes, 5)
    }

    func testSave_MalformedPolicy_IsNotOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try "invalid policy".write(to: url, atomically: true, encoding: .utf8)
        let store = PolicySettingsStore(url: url, home: url.deletingLastPathComponent())
        XCTAssertThrowsError(try store.save(AppPreferences(), accounts: []))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "invalid policy")
    }
}

@MainActor
final class SettingsFailureTests: XCTestCase {
    func testSave_FailedPolicyWrite_RollsBackVisibleSettings() async {
        let model = UsageModel(provider: FailingSettingsProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        model.setPollingMinutes(5)
        XCTAssertEqual(model.preferences.pollingMinutes, 15)
        XCTAssertNotNil(model.settingsError)
    }
}

@MainActor
private struct FailingSettingsProvider: AppModel.UsageProvider {
    func refresh() async throws -> [AccountUsage] { [] }
    func saveSettings(_ preferences: AppPreferences, accounts: [AccountUsage]) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

final class PolicyConcurrencyTests: XCTestCase {
    func testSave_OnlyEditedFieldsChange_AndFractionalTargetsSurvive() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("policy.toml")
        let initial = "[[accounts]]\nid = \"one\"\nprovider = \"codex\"\nconfig_dir = \"/fixture/codex\"\ntarget_low = 40\ntarget_high = 72.5\n"
        try initial.write(to: url, atomically: true, encoding: .utf8)
        let store = PolicySettingsStore(url: url, home: directory)
        let baseline = try store.load(into: AppPreferences())
        XCTAssertEqual(baseline.accounts["one"]?.targetHigh, 72.5)
        try initial.replacingOccurrences(of: "72.5", with: "50").write(to: url, atomically: true, encoding: .utf8)
        var edited = baseline
        edited.pollingMinutes = 5
        try store.save(edited, accounts: [], baseline: baseline)
        XCTAssertEqual(try Policy.load(url, home: directory).accounts.first?.targetHigh, 50)
        let output = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(output.contains("config_dir = \"/fixture/codex\""))
    }

    func testSave_ConflictingExternalChange_IsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("policy.toml")
        let initial = "[[accounts]]\nid = \"one\"\nprovider = \"codex\"\nconfig_dir = \"/fixture/codex\"\ntarget_low = 40\ntarget_high = 75\n"
        try initial.write(to: url, atomically: true, encoding: .utf8)
        let store = PolicySettingsStore(url: url, home: directory)
        let baseline = try store.load(into: AppPreferences())
        try initial.replacingOccurrences(of: "75", with: "50").write(to: url, atomically: true, encoding: .utf8)
        var edited = baseline
        edited.accounts["one"]?.targetHigh = 60
        XCTAssertThrowsError(try store.save(edited, accounts: [], baseline: baseline))
        XCTAssertEqual(try Policy.load(url, home: directory).accounts.first?.targetHigh, 50)
    }
}

final class PolicyEncodingTests: XCTestCase {
    func testSavedPolicy_PathsUseStandardTOMLStringEscapes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("policy.toml")
        try "[[accounts]]\nid = \"one\"\nprovider = \"codex\"\nconfig_dir = \"/fixture/codex\"\n"
            .write(to: url, atomically: true, encoding: .utf8)
        try PolicySettingsStore(url: url, home: directory).save(AppPreferences(), accounts: [])
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("config_dir = \"/fixture/codex\""))
    }
}

@MainActor
final class SettingsErrorCopyTests: XCTestCase {
    func testSaveFailure_NamesSettingsFileAndRecoveryAction() {
        let model = UsageModel(provider: FailingSettingsProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        model.setPollingMinutes(30)
        XCTAssertTrue(model.settingsError?.contains("~/.config/leeway/policy.toml") == true)
        XCTAssertTrue(model.settingsError?.contains("writable and valid TOML") == true)
    }

    func testLoadFailure_NamesSettingsFileAndRecoveryAction() {
        let model = UsageModel(provider: UnreadableProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertTrue(model.settingsError?.contains("~/.config/leeway/policy.toml") == true)
        XCTAssertTrue(model.settingsError?.contains("readable and valid TOML") == true)
    }
}

@MainActor
private struct UnreadableProvider: AppModel.UsageProvider {
    func refresh() async throws -> [AccountUsage] { [] }
    func loadSettings(_ stored: AppPreferences) throws -> AppPreferences { throw CocoaError(.fileReadNoPermission) }
}
