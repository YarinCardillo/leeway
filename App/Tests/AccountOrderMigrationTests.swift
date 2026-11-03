import AppModel
import XCTest

@MainActor
final class AccountOrderMigrationTests: XCTestCase {
    func testLegacyPin_BecomesFirstManualAccountAndIsNotEncoded() throws {
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppPreferences())) as? [String: Any])
        fields["pinnedID"] = "low"
        fields["accountOrderMode"] = "mostAtRisk"
        fields["manualAccountOrder"] = ["high", "low"]
        let value = try JSONDecoder().decode(AppPreferences.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertEqual(value.accountOrderMode, .manual)
        XCTAssertEqual(value.manualAccountOrder, ["low", "high"])
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        XCTAssertNil(encoded["pinnedID"])
    }

    func testLegacyPinWithoutOrder_MigratesSilentlyOnLoadAndSave() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppPreferences())) as? [String: Any])
        fields.removeValue(forKey: "accountOrderMode")
        fields.removeValue(forKey: "manualAccountOrder")
        fields["pinnedID"] = "low"
        defaults.set(try JSONSerialization.data(withJSONObject: fields), forKey: "app.preferences.v1")
        let model = UsageModel(provider: TestProvider(), defaults: defaults)
        await model.refresh()
        XCTAssertEqual(model.enabledAccounts.map(\.id), ["low", "high"])
        XCTAssertEqual(model.selectedAccount?.id, "low")
        let saved = try XCTUnwrap(defaults.data(forKey: "app.preferences.v1"))
        XCTAssertNil((try JSONSerialization.jsonObject(with: saved) as? [String: Any])?["pinnedID"])
    }

    func testManualOrder_FirstUnknownReadingIsNotReplacedByAnotherAccount() async {
        let model = UsageModel(provider: UnknownFirstProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        model.setAccountOrderMode(.manual)
        model.moveAccounts(fromOffsets: [1], toOffset: 0)
        XCTAssertEqual(model.enabledAccounts.first?.id, "low")
        XCTAssertEqual(model.selectedAccount?.id, "low")
        XCTAssertNil(model.selectedAccount?.weeklyUsed)
    }
}

@MainActor
private struct UnknownFirstProvider: UsageProvider {
    func refresh() async throws -> [AccountUsage] {
        var values = TestProvider.readings
        values[0].weeklyUsed = nil
        return values
    }
}

extension AccountOrderMigrationTests {
    func testLegacyPinWithExistingOrder_IsRemovedFromStorageOnLoad() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppPreferences())) as? [String: Any])
        fields["pinnedID"] = "low"
        fields["accountOrderMode"] = "manual"
        fields["manualAccountOrder"] = ["high", "low"]
        defaults.set(try JSONSerialization.data(withJSONObject: fields), forKey: "app.preferences.v1")
        let model = UsageModel(provider: TestProvider(), defaults: defaults)
        XCTAssertEqual(model.preferences.manualAccountOrder, ["low", "high"])
        let saved = try XCTUnwrap(defaults.data(forKey: "app.preferences.v1"))
        XCTAssertNil((try JSONSerialization.jsonObject(with: saved) as? [String: Any])?["pinnedID"])
    }
}
