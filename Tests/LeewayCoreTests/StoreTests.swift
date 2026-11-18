import Foundation
import CSQLite
import Testing
@testable import LeewayCore

func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("leeway-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Test func storeKeepsLatestAndRepeatedReadingsAreIdempotent() throws {
    let store = try SnapshotStore(path: ":memory:")
    let older = Snapshot(account: "first", at: now.addingTimeInterval(-hour), sevenDay: UsageWindow(pct: 20, resetsAt: reset))
    let newer = Snapshot(account: "first", at: now, sevenDay: UsageWindow(pct: 30, resetsAt: reset))
    try store.record(newer)
    try store.record(older)
    try store.record(newer)
    #expect(try store.latest("first") == newer)
    #expect(try store.windowHistory("first", resetsAt: reset).map(\.pct) == [20, 30])
    #expect(try store.latest("absent") == nil)
}

@Test func storeIncludesTimestampWindowDespiteResetDriftAndUsesBoundParameters() throws {
    let store = try SnapshotStore(path: ":memory:")
    for (index, delta) in [-7 * 24 * hour, -3601, -3600, 0, 3600, 3601].enumerated() {
        try store.record(Snapshot(account: "x'; DROP TABLE snapshots;--", at: now.addingTimeInterval(Double(index)),
            sevenDay: UsageWindow(pct: Double(index), resetsAt: reset.addingTimeInterval(delta))))
    }
    #expect(try store.windowHistory("x'; DROP TABLE snapshots;--", resetsAt: reset).map(\.pct) == [0, 1, 2, 3, 4, 5])
}

@Test func storePersistsFailuresAcrossConnectionsAndClearsAfterSuccess() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("usage.sqlite").path
    let store = try SnapshotStore(path: path)
    try store.markFailed("first", at: now)
    #expect(try SnapshotStore(path: path).hasFailure("first"))
    try store.record(Snapshot(account: "first", at: now,
        fiveHour: UsageWindow(pct: 5, resetsAt: reset), sevenDay: UsageWindow(pct: 20, resetsAt: reset)))
    #expect(try !store.hasFailure("first"))
}

@Test func store_FreshWeeklyReading_DoesNotInheritExpiredFiveHourTimestamp() throws {
    let store = try SnapshotStore(path: ":memory:")
    try store.record(Snapshot(account: "one", at: now.addingTimeInterval(-24 * hour),
        fiveHour: UsageWindow(pct: 5, resetsAt: now.addingTimeInterval(-hour)), sevenDay: UsageWindow(pct: 10, resetsAt: reset)))
    try store.record(Snapshot(account: "one", at: now, sevenDay: UsageWindow(pct: 13, resetsAt: reset)))
    #expect(try store.latest("one")?.at == now)
    #expect(try !store.hasFailure("one"))
}

@Test func store_WindowBoundaryAndResetDrift_MatchEngineTimestampFilter() throws {
    let store = try SnapshotStore(path: ":memory:")
    let start = reset.addingTimeInterval(-Forecaster.week)
    try store.record(Snapshot(account: "one", at: start,
        sevenDay: UsageWindow(pct: 1, resetsAt: reset)))
    try store.record(Snapshot(account: "one", at: now,
        sevenDay: UsageWindow(pct: 13, resetsAt: reset.addingTimeInterval(7200))))
    #expect(try store.windowHistory("one", resetsAt: reset).map(\.pct) == [1, 13])
}

@Test func failureReason_SurvivesReopeningAndEndsWithTheNextReading() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("history.sqlite").path
    try SnapshotStore(path: path).markFailed("first", at: now, reason: .notSignedIn)
    let reopened = try SnapshotStore(path: path)
    #expect(try reopened.failureReason("first") == .notSignedIn)
    #expect(try reopened.failureReason("first", after: now) == nil)
    try reopened.record(Snapshot(account: "first", at: now.addingTimeInterval(60), sevenDay: UsageWindow(pct: 5, resetsAt: reset)))
    #expect(try reopened.failureReason("first") == nil)
}

@Test func failuresTableWithoutReasonColumn_IsMigratedInPlace() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("history.sqlite").path
    var legacy: OpaquePointer?
    #expect(sqlite3_open(path, &legacy) == SQLITE_OK)
    #expect(sqlite3_exec(legacy, "CREATE TABLE failures (account TEXT PRIMARY KEY NOT NULL, at REAL NOT NULL); INSERT INTO failures VALUES ('first', 100)", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(legacy)
    let store = try SnapshotStore(path: path)
    #expect(try store.hasFailure("first"))
    #expect(try store.failureReason("first") == nil)
    try store.markFailed("first", at: now, reason: .timeout)
    #expect(try store.failureReason("first") == .timeout)
}

@Test func refreshRequests_CollapseAndAreTakenOnce() throws {
    let store = try SnapshotStore(path: ":memory:")
    #expect(try !store.hasRefreshRequest())
    #expect(try !store.takeRefreshRequest())
    try store.requestRefresh(at: now)
    try store.requestRefresh(at: now.addingTimeInterval(5))
    #expect(try store.hasRefreshRequest())
    #expect(try store.takeRefreshRequest())
    #expect(try !store.takeRefreshRequest())
}

private func storedSchemaVersion(_ path: String) -> Int32 {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return -1 }
    defer { sqlite3_close(connection) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else { return -1 }
    defer { sqlite3_finalize(statement) }
    return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : -1
}

@Test func store_FreshDatabase_RecordsTheCurrentSchemaVersion() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("history.sqlite").path
    _ = try SnapshotStore(path: path)
    #expect(SnapshotStore.schemaVersion == 1)
    #expect(storedSchemaVersion(path) == SnapshotStore.schemaVersion)
}

@Test func store_UnversionedLegacyDatabase_IsStampedWithoutLosingRows() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("history.sqlite").path
    var legacy: OpaquePointer?
    #expect(sqlite3_open(path, &legacy) == SQLITE_OK)
    #expect(sqlite3_exec(legacy, "CREATE TABLE failures (account TEXT PRIMARY KEY NOT NULL, at REAL NOT NULL); INSERT INTO failures VALUES ('first', 100)", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(legacy)
    #expect(storedSchemaVersion(path) == 0)
    let store = try SnapshotStore(path: path)
    #expect(try store.hasFailure("first"))
    #expect(storedSchemaVersion(path) == SnapshotStore.schemaVersion)
}

@Test func store_NewerSchemaThanTheBinary_IsRefusedAndTheFileIsUntouched() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("history.sqlite")
    let newer = SnapshotStore.schemaVersion + 1
    var connection: OpaquePointer?
    #expect(sqlite3_open(file.path, &connection) == SQLITE_OK)
    #expect(sqlite3_exec(connection, "CREATE TABLE future (id INTEGER); PRAGMA user_version = \(newer)", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(connection)
    let before = try Data(contentsOf: file)
    do {
        _ = try SnapshotStore(path: file.path)
        Issue.record("a store from a newer leeway was opened")
    } catch CoreError.storeNewerThanBinary {
    } catch { Issue.record("unexpected error \(error)") }
    #expect(try Data(contentsOf: file) == before)
    #expect(storedSchemaVersion(file.path) == newer)
}
