import AppModel
import XCTest

final class UpdateCheckTests: XCTestCase {
    func testMissingFeed_ReportsUnavailableWithoutStartingAnUpdater() {
        var didStart = false
        let result = UpdateCheckResult.request(isConfigured: false, canCheck: false) { didStart = true }
        XCTAssertEqual(result, .notConfigured)
        XCTAssertFalse(didStart)
    }

    func testConfiguredFeed_StartsOnlyWhenReady() {
        var count = 0
        XCTAssertEqual(UpdateCheckResult.request(isConfigured: true, canCheck: false) { count += 1 }, .busy)
        XCTAssertEqual(UpdateCheckResult.request(isConfigured: true, canCheck: true) { count += 1 }, .started)
        XCTAssertEqual(count, 1)
    }
}
