import Foundation
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
