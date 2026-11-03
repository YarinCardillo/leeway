import AppModel
import XCTest

final class ForecastMeterLayoutTests: XCTestCase {
    private func account(used: Double? = 62, week: Double? = 70, recent: Double? = 84,
                         target: ClosedRange<Double> = 65...75) -> AccountUsage {
        var value = AccountUsage(id: "work", name: "Work", source: "claude", weeklyUsed: used,
                                 fiveHourUsed: nil, reset: nil, fiveHourReset: nil, weekForecast: week,
                                 recentForecast: recent, recordedAt: nil, history: [])
        value.targetLow = target.lowerBound
        value.targetHigh = target.upperBound
        return value
    }

    func testLayout_NoReading_IsNil() {
        XCTAssertNil(ForecastMeterLayout(account: account(used: nil)))
    }

    func testLayout_ForecastBelowLimit_KeepsHundredPercentDomain() throws {
        let layout = try XCTUnwrap(ForecastMeterLayout(account: account()))
        XCTAssertEqual(layout.domainMaximum, 100)
        XCTAssertEqual(layout.usedFraction, 0.62, accuracy: 0.0001)
        XCTAssertEqual(layout.forecastFractions?.lowerBound ?? 0, 0.70, accuracy: 0.0001)
        XCTAssertEqual(layout.forecastFractions?.upperBound ?? 0, 0.84, accuracy: 0.0001)
        XCTAssertEqual(layout.targetFractions.lowerBound, 0.65, accuracy: 0.0001)
        XCTAssertEqual(layout.targetFractions.upperBound, 0.75, accuracy: 0.0001)
    }

    // Owner revision: overflow is clipped and never changes the common quota scale.
    func testLayout_ForecastPastLimit_ClampsWithoutRescalingTargets() throws {
        let layout = try XCTUnwrap(ForecastMeterLayout(account: account(used: 96, week: 102, recent: 116)))
        XCTAssertEqual(layout.domainMaximum, 100)
        XCTAssertEqual(layout.usedFraction, 0.96, accuracy: 0.0001)
        XCTAssertEqual(layout.forecastFractions, 1...1)
        XCTAssertEqual(layout.targetFractions, 0.65...0.75)
    }

    func testLayout_ForecastCrossesLimit_ClampsOnlyUpperEndpoint() throws {
        let layout = try XCTUnwrap(ForecastMeterLayout(account: account(week: 84, recent: 116, target: 75...100)))
        XCTAssertEqual(layout.forecastFractions, 0.84...1)
        XCTAssertEqual(layout.targetFractions, 0.75...1)
    }

    func testLayout_DifferentAccounts_UseIdenticalProportions() throws {
        let regular = try XCTUnwrap(ForecastMeterLayout(account: account()))
        let overflow = try XCTUnwrap(ForecastMeterLayout(account: account(recent: 250)))
        XCTAssertEqual(regular.usedFraction, overflow.usedFraction)
        XCTAssertEqual(regular.targetFractions, overflow.targetFractions)
    }

    func testLayout_NoForecast_HasNoForecastRange() throws {
        let layout = try XCTUnwrap(ForecastMeterLayout(account: account(week: nil, recent: nil)))
        XCTAssertNil(layout.forecastFractions)
    }

    func testLayout_UsedPastLimit_StaysInsideTheDomain() throws {
        let layout = try XCTUnwrap(ForecastMeterLayout(account: account(used: 130, week: 130, recent: 130)))
        XCTAssertLessThanOrEqual(layout.usedFraction, 1)
        XCTAssertEqual(layout.domainMaximum, 100)
    }
}

extension ForecastMeterLayoutTests {
    func testLayout_NarrowTargetsAtEitherEndpoint_KeepTwoSeparateTicks() throws {
        for target in [0.0...0.1, 99.9...100.0, 49.9...50.0] {
            let layout = try XCTUnwrap(ForecastMeterLayout(account: account(target: target)))
            let ticks = layout.targetTickPositions(width: 290)
            XCTAssertGreaterThanOrEqual(ticks.upperBound - ticks.lowerBound, 5)
            XCTAssertGreaterThanOrEqual(ticks.lowerBound, 1.5)
            XCTAssertLessThanOrEqual(ticks.upperBound, 288.5)
            XCTAssertEqual(layout.targetFractions, target.lowerBound / 100...target.upperBound / 100)
        }
    }

    func testLayout_NormalTargetTicks_KeepTheirExactPositions() throws {
        let layout = try XCTUnwrap(ForecastMeterLayout(account: account(target: 65...75)))
        XCTAssertEqual(layout.targetTickPositions(width: 200), 130...150)
    }
}
