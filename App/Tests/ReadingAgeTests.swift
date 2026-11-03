import AppModel
import XCTest

final class ReadingAgeTests: XCTestCase {
    func testReadingAge_OnlyOlderThanTwoPollingIntervalsIsStale() {
        let now = Date(timeIntervalSince1970: 1800000000)
        var account = AccountUsage(id: "work", name: "Work", source: "Claude", weeklyUsed: 62,
            fiveHourUsed: nil, reset: nil, fiveHourReset: nil, weekForecast: nil, recentForecast: nil,
            recordedAt: now.addingTimeInterval(-600), history: [])
        account.isStale = true
        XCTAssertFalse(account.isReadingOld(pollingMinutes: 5, now: now))
        XCTAssertTrue(account.isReadingOld(pollingMinutes: 5, now: now.addingTimeInterval(1)))
        XCTAssertFalse(account.isReadingOld(pollingMinutes: 15, now: now.addingTimeInterval(1)))
        XCTAssertFalse(account.isReadingOld(pollingMinutes: 5, now: now.addingTimeInterval(-1200)))
    }
}
