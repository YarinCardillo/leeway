import AppCore
import AppModel
import LeewayCore
import XCTest

final class TargetRangeTests: XCTestCase {
    func testMapping_UsesRangeOverlapAndEarlySeverity() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let forecast = Forecast(averagePctAtReset: 102, recentPctAtReset: 120, rangeLow: 102, rangeHigh: 120,
            nextRoundPct: 63, exhaustsAt: reset.addingTimeInterval(-13 * 3600), confidence: .medium)
        let status = AccountStatus(id: "one", label: "One", provider: .claude, configDir: "/fixture",
            sevenDay: UsageWindow(pct: 62, resetsAt: reset), forecast: forecast, targetLow: 75, targetHigh: 100)
        let account = CoreSnapshotMapper.map(StatusDocument(generatedAt: reset, accounts: [status]))[0]
        XCTAssertEqual(account.targetLow, 75)
        XCTAssertEqual(account.targetHigh, 100)
        XCTAssertEqual(account.status, .over)
        XCTAssertEqual(account.severity, .red)
        XCTAssertEqual(account.hoursEarly, 13)
    }

    func testPreferences_ObsoleteCeilingDoesNotChangeDefaultTargets() throws {
        let old = Data(#"{"name":"Work","isEnabled":true,"ceiling":75,"aliases":[]}"#.utf8)
        let choice = try JSONDecoder().decode(AccountPreference.self, from: old)
        XCTAssertEqual(choice.targetLow, 75)
        XCTAssertEqual(choice.targetHigh, 100)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(choice)) as? [String: Any])
        XCTAssertNil(raw["ceiling"])
        XCTAssertEqual(raw["targetLow"] as? Double, 75)
        XCTAssertEqual(raw["targetHigh"] as? Double, 100)
    }

    func testPreferences_ExplicitTargetsIgnoreObsoleteCeiling() throws {
        let data = Data(#"{"ceiling":75,"targetLow":60,"targetHigh":90}"#.utf8)
        let choice = try JSONDecoder().decode(AccountPreference.self, from: data)
        XCTAssertEqual(choice.targetLow, 60)
        XCTAssertEqual(choice.targetHigh, 90)
    }

    func testRangeAdjustment_StepsBothHandlesWithoutCrossing() {
        XCTAssertEqual(TargetRangeAdjustment.move(.low, increasing: true, low: 75, high: 100), 80)
        XCTAssertEqual(TargetRangeAdjustment.move(.high, increasing: false, low: 75, high: 100), 95)
        XCTAssertEqual(TargetRangeAdjustment.move(.low, increasing: true, low: 95, high: 100), 95)
        XCTAssertEqual(TargetRangeAdjustment.move(.high, increasing: false, low: 0, high: 5), 5)
        XCTAssertEqual(TargetRangeAdjustment.move(.low, increasing: false, low: 0, high: 100), 0)
        XCTAssertEqual(TargetRangeAdjustment.move(.high, increasing: true, low: 0, high: 100), 100)
        XCTAssertEqual(TargetRangeAdjustment.move(.low, increasing: true, low: 72.5, high: 100), 75)
    }
}

@MainActor
final class TargetRangeModelTests: XCTestCase {
    func testTarget_BoundsSaveTogetherAndInvalidGapIsRejected() async {
        let model = UsageModel(provider: TestProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        model.setTarget(low: 60, high: 80, for: "low")
        XCTAssertEqual(model.accounts[0].targetLow, 60)
        XCTAssertEqual(model.accounts[0].targetHigh, 80)
        XCTAssertEqual(model.accounts[0].status, .onTarget)
        model.setTarget(low: 80, high: 80, for: "low")
        model.setTarget(low: 61, high: 80, for: "low")
        XCTAssertEqual(model.accounts[0].targetLow, 60)
        XCTAssertEqual(model.accounts[0].targetHigh, 80)
    }
}

extension TargetRangeTests {
    func testRangeAdjustment_FractionalOppositeBoundStillUsesFivePointGrid() {
        XCTAssertEqual(TargetRangeAdjustment.move(.low, increasing: true, low: 65, high: 72.5), 65)
        XCTAssertEqual(TargetRangeAdjustment.move(.high, increasing: false, low: 72.5, high: 80), 80)
    }

    func testRangeAdjustment_CloseHandlesChooseNearestPointerValue() {
        XCTAssertEqual(TargetRangeAdjustment.nearest(to: 75, low: 75, high: 80), .low)
        XCTAssertEqual(TargetRangeAdjustment.nearest(to: 80, low: 75, high: 80), .high)
    }
}

extension TargetRangeModelTests {
    func testTarget_MovingOneHandlePreservesAnUneditedFractionalBound() async {
        let provider = FractionalTargetProvider()
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        model.setTarget(low: 60, high: 72.5, for: "low")
        XCTAssertEqual(model.accounts[0].targetLow, 60)
        XCTAssertEqual(model.accounts[0].targetHigh, 72.5)
    }
}

@MainActor
private struct FractionalTargetProvider: AppModel.UsageProvider {
    func refresh() async throws -> [AccountUsage] {
        var account = TestProvider.readings[0]
        account.targetLow = 62.5
        account.targetHigh = 72.5
        return [account]
    }
}

extension TargetRangeTests {
    func testRangeAdjustment_NarrowPolicyRangeNeverReversesArrowDirection() {
        XCTAssertEqual(TargetRangeAdjustment.move(.low, increasing: true, low: 74, high: 75), 74)
        XCTAssertEqual(TargetRangeAdjustment.move(.high, increasing: false, low: 75, high: 76), 76)
        XCTAssertEqual(TargetRangeAdjustment.move(.low, increasing: false, low: 74, high: 75), 70)
        XCTAssertEqual(TargetRangeAdjustment.move(.high, increasing: true, low: 75, high: 76), 80)
    }
}
