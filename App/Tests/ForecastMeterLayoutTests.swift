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
        XCTAssertNil(layout.limitFraction)
        XCTAssertEqual(layout.usedFraction, 0.62, accuracy: 0.0001)
        XCTAssertEqual(layout.forecastFractions?.lowerBound ?? 0, 0.70, accuracy: 0.0001)
        XCTAssertEqual(layout.forecastFractions?.upperBound ?? 0, 0.84, accuracy: 0.0001)
        XCTAssertEqual(layout.targetFractions.lowerBound, 0.65, accuracy: 0.0001)
        XCTAssertEqual(layout.targetFractions.upperBound, 0.75, accuracy: 0.0001)
    }

    func testLayout_ForecastPastLimit_ExtendsDomainAndMarksTheLimit() throws {
        let layout = try XCTUnwrap(ForecastMeterLayout(account: account(used: 96, week: 102, recent: 116)))
        XCTAssertEqual(layout.domainMaximum, 120)
        XCTAssertEqual(try XCTUnwrap(layout.limitFraction), 100.0 / 120.0, accuracy: 0.0001)
        XCTAssertEqual(layout.forecastFractions?.upperBound ?? 0, 116.0 / 120.0, accuracy: 0.0001)
    }

    func testLayout_NoForecast_HasNoForecastRange() throws {
        let layout = try XCTUnwrap(ForecastMeterLayout(account: account(week: nil, recent: nil)))
        XCTAssertNil(layout.forecastFractions)
    }

    func testLayout_UsedPastLimit_StaysInsideTheDomain() throws {
        let layout = try XCTUnwrap(ForecastMeterLayout(account: account(used: 130, week: 130, recent: 130)))
        XCTAssertLessThanOrEqual(layout.usedFraction, 1)
        XCTAssertEqual(layout.domainMaximum, 130)
    }
}
