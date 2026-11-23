import AppModel
import XCTest

@MainActor
final class ChartInspectionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1800000000)

    private func account() -> AccountUsage {
        AccountUsage(id: "work", name: "Work", source: "Claude", weeklyUsed: 60,
            fiveHourUsed: nil, reset: start.addingTimeInterval(7 * 86400), fiveHourReset: nil,
            weekForecast: 100, recentForecast: 117, recordedAt: start.addingTimeInterval(3 * 86400),
            history: [UsagePoint(date: start, used: 10), UsagePoint(date: start.addingTimeInterval(86400), used: 30)])
    }

    func testDomain_ShowsAboveLimitForecastWithRoomForLabels() {
        XCTAssertEqual(account().chartYDomain, 0...127)
    }

    func testReadout_PastSelectsNearestMeasurement_AndFutureInterpolatesBothForecasts() throws {
        let value = account()
        let past = try XCTUnwrap(value.chartReadout(at: start.addingTimeInterval(86400 + 100)))
        XCTAssertEqual(past.date, start.addingTimeInterval(86400))
        XCTAssertEqual(past.lower, 30)
        XCTAssertEqual(past.upper, 30)
        XCTAssertFalse(past.isForecast)
        let middle = try XCTUnwrap(value.chartReadout(at: start.addingTimeInterval(5 * 86400)))
        XCTAssertEqual(middle.lower, 80)
        XCTAssertEqual(middle.upper, 88.5)
        XCTAssertTrue(middle.isForecast)
        let end = try XCTUnwrap(value.chartReadout(at: start.addingTimeInterval(7 * 86400)))
        XCTAssertEqual(end.lower, 100)
        XCTAssertEqual(end.upper, 117)
    }

    func testInspectionPoints_AreOrderedAndIncludeLiveAnchorAndReset() throws {
        let value = account()
        let points = value.chartInspectionPoints
        XCTAssertEqual(points.first?.lower, 10)
        XCTAssertEqual(points.last?.upper, 117)
        XCTAssertEqual(points.filter { !$0.isForecast }.map(\.lower), [10, 30, 60])
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
        for point in points { XCTAssertEqual(value.chartReadout(at: point.date), point) }
    }
}

extension ChartInspectionTests {
    func testKeyboardStepping_VisitsSameReadoutsAndStopsAtEnds() {
        let account = account()
        let selection = ChartSelection()
        selection.step(forward: true, in: account.chartInspectionPoints)
        XCTAssertEqual(selection.date, start)
        selection.step(forward: false, in: account.chartInspectionPoints)
        XCTAssertEqual(selection.date, start)
        selection.step(forward: true, in: account.chartInspectionPoints)
        XCTAssertEqual(account.chartReadout(at: selection.date!)?.lower, 30)
    }
}

extension ChartInspectionTests {
    func testReadout_HistoryNewerThanReadingNeverProjectsBelowItsAnchor() throws {
        let value = AccountUsage(id: "work", name: "Work", source: "Claude", weeklyUsed: 30,
            fiveHourUsed: nil, reset: start.addingTimeInterval(7 * 86400), fiveHourReset: nil,
            weekForecast: 40, recentForecast: 50, recordedAt: start,
            history: [UsagePoint(date: start.addingTimeInterval(86400), used: 60)])
        let end = try XCTUnwrap(value.chartReadout(at: start.addingTimeInterval(7 * 86400)))
        XCTAssertEqual(end.lower, 60)
        XCTAssertEqual(end.upper, 60)
    }
}

extension ChartInspectionTests {
    /// A Codex account: readings arrive only when Codex works, here at 1 h (30%) and 12 h (32%).
    private func activityBased() -> AccountUsage {
        var value = AccountUsage(id: "codex", name: "Codex", source: "Codex", weeklyUsed: 32, fiveHourUsed: nil,
            reset: start.addingTimeInterval(7 * 86400), fiveHourReset: nil, weekForecast: 60, recentForecast: 70,
            recordedAt: start.addingTimeInterval(12 * 3600), history: [UsagePoint(date: start.addingTimeInterval(3600), used: 30)])
        value.isActivityBased = true
        return value
    }

    func testReadout_ActivityBased_HoldsTheLastReadingAtTheCursorTime() throws {
        let cursor = start.addingTimeInterval(6 * 3600 + 17)
        let readout = try XCTUnwrap(activityBased().chartReadout(at: cursor))
        XCTAssertEqual(readout.date, cursor)
        XCTAssertEqual(readout.lower, 30)
        XCTAssertEqual(readout.upper, 30)
        XCTAssertFalse(readout.isForecast)
    }

    func testReadout_ActivityBased_BeforeTheFirstReadingShowsTheFirstReading() throws {
        let readout = try XCTUnwrap(activityBased().chartReadout(at: start))
        XCTAssertEqual(readout.date, start.addingTimeInterval(3600))
        XCTAssertEqual(readout.lower, 30)
    }

    func testInspectionPoints_ActivityBased_RoundTripThroughTheReadout() {
        let value = activityBased()
        XCTAssertEqual(value.chartInspectionPoints.filter { !$0.isForecast }.map(\.lower), [30, 32])
        for point in value.chartInspectionPoints { XCTAssertEqual(value.chartReadout(at: point.date), point) }
    }
}

extension ChartInspectionTests {
    func testReadout_EstimatedSampleIsMarked_RealOneIsNot() throws {
        var value = account()
        value = AccountUsage(id: value.id, name: value.name, source: value.source, weeklyUsed: value.weeklyUsed,
            fiveHourUsed: nil, reset: value.reset, fiveHourReset: nil, weekForecast: value.weekForecast,
            recentForecast: value.recentForecast, recordedAt: value.recordedAt,
            history: [UsagePoint(date: start, used: 10, isEstimated: true), UsagePoint(date: start.addingTimeInterval(86400), used: 30)])
        XCTAssertEqual(try XCTUnwrap(value.chartReadout(at: start)).isEstimated, true)
        XCTAssertEqual(try XCTUnwrap(value.chartReadout(at: start.addingTimeInterval(86400))).isEstimated, false)
        XCTAssertEqual(try XCTUnwrap(value.chartReadout(at: start.addingTimeInterval(6 * 86400))).isEstimated, false)
    }
}
