import AppModel
import XCTest

final class ProjectLinksTests: XCTestCase {
    func testSource_PointsToThePublicRepositoryOverHTTPS() {
        XCTAssertEqual(ProjectLinks.source.absoluteString, "https://github.com/YarinCardillo/leeway")
    }
}
