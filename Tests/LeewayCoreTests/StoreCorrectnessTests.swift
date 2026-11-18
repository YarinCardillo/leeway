import Foundation
import CSQLite
import Testing
@testable import LeewayCore

private func storedVersion(_ path: String) -> Int32 {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return -1 }
    defer { sqlite3_close(connection) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else { return -1 }
    defer { sqlite3_finalize(statement) }
    return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : -1
}

@Test(.timeLimit(.minutes(1)))
func store_OlderBuildStartingWhileANewerOneMigrates_NeverLowersTheStoredVersion() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("history.sqlite").path
    let newerBuild = DispatchGroup()
    _ = try SnapshotStore(path: path, schemaVersion: 1, whileMigrating: {
        newerBuild.enter()
        DispatchQueue.global().async { defer { newerBuild.leave() }; _ = try? SnapshotStore(path: path) }
        _ = newerBuild.wait(timeout: .now() + 0.5)
    })
    newerBuild.wait()
    #expect(storedVersion(path) == Int32(SnapshotStore.schemaVersion))
}

@Test func store_RealReadingAtTheTimestampOfAnEstimate_ReplacesIt() throws {
    let store = try SnapshotStore(path: ":memory:")
    let anchor = Snapshot(account: "a", at: now, sevenDay: UsageWindow(pct: 30, resetsAt: reset))
    let tie = now.addingTimeInterval(-hour)
    try store.record(anchor, estimated: [HistoryPoint(at: tie, pct: 10, estimated: true)])
    let real = Snapshot(account: "a", at: tie, sevenDay: UsageWindow(pct: 20, resetsAt: reset))
    try store.record(real)
    #expect(try store.windowHistory("a", resetsAt: reset) == [HistoryPoint(at: tie, pct: 20), HistoryPoint(at: now, pct: 30)])
    #expect(try store.latest("a")?.at == now)
}

@Test func store_EstimateNeverReplacesAReal_AndARealNeverReplacesAnotherReal() throws {
    let store = try SnapshotStore(path: ":memory:")
    let first = Snapshot(account: "a", at: now, sevenDay: UsageWindow(pct: 20, resetsAt: reset))
    try store.record(first)
    try store.record(Snapshot(account: "a", at: now.addingTimeInterval(hour), sevenDay: UsageWindow(pct: 40, resetsAt: reset)),
        estimated: [HistoryPoint(at: now, pct: 99, estimated: true)])
    try store.record(Snapshot(account: "a", at: now, sevenDay: UsageWindow(pct: 77, resetsAt: reset)))
    #expect(try store.windowHistory("a", resetsAt: reset).first == HistoryPoint(at: now, pct: 20))
}

@Test func store_AccountWithOnlyEstimatedPoints_HasHistoryButNoReading() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("history.sqlite").path
    let store = try SnapshotStore(path: path)
    let estimate = HistoryPoint(at: now.addingTimeInterval(-hour), pct: 5, estimated: true)
    try store.record(Snapshot(account: "x", at: now, sevenDay: UsageWindow(pct: 5, resetsAt: reset)), estimated: [estimate])
    var connection: OpaquePointer?
    try #require(sqlite3_open(path, &connection) == SQLITE_OK)
    try #require(sqlite3_exec(connection, "DELETE FROM snapshots WHERE account = 'x' AND estimated = 0", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(connection)
    #expect(try store.latest("x") == nil)
    #expect(try !store.hasReadings("x"))
    #expect(try store.windowHistory("x", resetsAt: reset) == [estimate])
}
