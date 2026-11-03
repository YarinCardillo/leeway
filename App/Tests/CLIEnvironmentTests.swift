import AppCore
import Foundation
import XCTest

final class CLIEnvironmentTests: XCTestCase {
    func testFinderEnvironment_FindsNativeAndHomebrewCLIs_WithoutReplacingCustomPath() {
        let result = CLIEnvironment.forApplication(home: URL(fileURLWithPath: "/fixture/home"), inherited: ["PATH": "/custom/bin:/usr/bin"])
        XCTAssertEqual(result["PATH"]?.components(separatedBy: ":").prefix(2), ["/custom/bin", "/usr/bin"])
        XCTAssertTrue(result["PATH"]!.contains("/fixture/home/.local/bin"))
        XCTAssertTrue(result["PATH"]!.contains("/opt/homebrew/bin"))
        XCTAssertTrue(result["PATH"]!.contains("/usr/local/bin"))
    }
}
