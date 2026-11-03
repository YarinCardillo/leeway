import CSQLite
import Foundation
import Testing
@testable import LeewayCore

func permissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
}

@Test(arguments: [true, false])
func finding7DatabaseAndExistingSidecarsArePrivate(existing: Bool) throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("leeway")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    let file = directory.appendingPathComponent("history.sqlite")
    var db: OpaquePointer?
    defer { if let db { sqlite3_close(db) } }
    if existing {
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "PRAGMA journal_mode=WAL; CREATE TABLE fixture (value INTEGER)", nil, nil, nil) == SQLITE_OK)
        for suffix in ["", "-wal", "-shm"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path + suffix)
        }
    }
    let store = try SnapshotStore(path: file.path)
    try store.record(Snapshot(account: "first", at: now,
        fiveHour: UsageWindow(pct: 5, resetsAt: reset), sevenDay: UsageWindow(pct: 20, resetsAt: reset)))
    #expect(try permissions(directory) == 0o700)
    #expect(try permissions(file) == 0o600)
    for suffix in ["-wal", "-shm", "-journal"] where FileManager.default.fileExists(atPath: file.path + suffix) {
        #expect(try permissions(URL(fileURLWithPath: file.path + suffix)) == 0o600)
    }
}

@Test func finding7CustomStorageDoesNotChangeSharedParentPermissions() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let shared = root.appendingPathComponent("shared")
    try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    _ = try SnapshotStore(path: shared.appendingPathComponent("custom.sqlite").path)
    #expect(try permissions(shared) == 0o755)
    let policy = shared.appendingPathComponent("policy.toml")
    try "poll_minutes = 5".write(to: policy, atomically: true, encoding: .utf8)
    _ = try Policy.load(policy, home: root)
    #expect(try permissions(shared) == 0o755)
    try PrivateStorage.write(Data("poll_minutes = 10".utf8), to: policy)
    #expect(try permissions(shared) == 0o755)
    #expect(try permissions(policy) == 0o600)
}
