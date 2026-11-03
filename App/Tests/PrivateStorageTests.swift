import AppCore
import AppModel
import Foundation
import LeewayCore
import XCTest

final class PrivateStorageTests: XCTestCase {
    func testFinding7_PolicyStaysPrivateOnLoadAndAtomicReplacement() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent(".config/leeway")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let file = directory.appendingPathComponent("policy.toml")
        try "poll_minutes = 15\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        let store = PolicySettingsStore(url: file, home: home)
        var preferences = try store.load(into: AppPreferences())
        XCTAssertEqual(try mode(directory), 0o700)
        XCTAssertEqual(try mode(file), 0o600)
        for minutes in [5, 10] {
            preferences.pollingMinutes = minutes
            try store.save(preferences, accounts: [])
            XCTAssertEqual(try mode(directory), 0o700)
            XCTAssertEqual(try mode(file), 0o600)
            XCTAssertEqual(try Policy.load(file, home: home).pollMinutes, minutes)
        }
        try FileManager.default.removeItem(at: directory)
        try store.save(preferences, accounts: [])
        XCTAssertEqual(try mode(directory), 0o700)
        XCTAssertEqual(try mode(file), 0o600)
    }

    @MainActor
    func testFinding7_LiveProviderProtectsHistoryDirectory() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try CoreUsageProvider.live(home: home, environment: [:])
        let directory = home.appendingPathComponent("Library/Application Support/leeway")
        XCTAssertEqual(try mode(directory), 0o700)
        XCTAssertEqual(try mode(directory.appendingPathComponent("history.sqlite")), 0o600)
    }

    private func mode(_ url: URL) throws -> Int {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
        return value.intValue & 0o777
    }
}
