import XCTest
@testable import AppModel

final class ChartSeriesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)
    private let end = Date(timeIntervalSince1970: 7 * 86400)

    private func at(_ hours: Double, _ used: Double) -> UsagePoint {
        UsagePoint(date: start.addingTimeInterval(hours * 3600), used: used)
    }

    private func account(history: [UsagePoint], reading: UsagePoint?) -> AccountUsage {
        AccountUsage(id: "a", name: "A", source: "probe", weeklyUsed: reading?.used, fiveHourUsed: nil,
                     reset: end, fiveHourReset: nil, weekForecast: 80, recentForecast: 90,
                     recordedAt: reading?.date, history: history)
    }

    func testChartSeries_ReadingNewerThanHistory_LineEndsOnTheReading() {
        let series = account(history: [at(1, 10), at(2, 20)], reading: at(3, 30)).chartSeries(from: start, to: end)
        XCTAssertEqual(series.line.last, at(3, 30))
        XCTAssertEqual(series.now, at(3, 30))
    }

    func testChartSeries_HistoryPastTheReading_LineAndDotShareTheNewestPoint() {
        let series = account(history: [at(1, 10), at(4, 40)], reading: at(3, 30)).chartSeries(from: start, to: end)
        XCTAssertEqual(series.now, at(4, 40))
        XCTAssertEqual(series.line.last, series.now)
        XCTAssertFalse(series.line.contains(at(3, 30)))
    }

    func testChartSeries_NoReading_DotIsTheLastHistoryPoint() {
        let series = account(history: [at(1, 10), at(2, 20)], reading: nil).chartSeries(from: start, to: end)
        XCTAssertEqual(series.now, at(2, 20))
        XCTAssertEqual(series.line, [at(1, 10), at(2, 20)])
    }

    func testChartSeries_PointsOutsideTheWeek_AreDropped() {
        let before = UsagePoint(date: start.addingTimeInterval(-3600), used: 5)
        let series = account(history: [before, at(1, 10)], reading: at(2, 20)).chartSeries(from: start, to: end)
        XCTAssertEqual(series.line, [at(1, 10), at(2, 20)])
    }
}


extension ChartSeriesTests {
    func testSingleSample_DrawsOnlyDotWithoutMeasuredSegment() {
        let point = at(80, 62)
        let series = account(history: [], reading: point).chartSeries(from: start, to: end)
        XCTAssertEqual(series.now, point)
        XCTAssertEqual(series.line, [point])
        XCTAssertEqual(series.measuredLine, [])
    }

    func testNearbySamples_DrawOnlyRealIntervalWithoutZeroOrWeekStart() {
        let points = [at(80, 62), at(80.01, 63)]
        let series = account(history: points, reading: nil).chartSeries(from: start, to: end)
        XCTAssertEqual(series.measuredLine, points)
        XCTAssertEqual(series.now, points.last)
        XCTAssertTrue(series.line.allSatisfy { $0.used > 0 && $0.date > start })
    }

    func testDuplicateTimestamps_KeepNewestSampleWithoutVerticalSegment() {
        let series = account(history: [at(80, 62), at(80, 63)], reading: nil).chartSeries(from: start, to: end)
        XCTAssertEqual(series.line, [at(80, 63)])
        XCTAssertEqual(series.measuredLine, [])
    }
}
