import Foundation
import CSQLite

/// Serialized, transactional snapshot storage. Errors never include database paths or data.
public final class SnapshotStore: @unchecked Sendable {
    /// The store layout this build reads and writes, kept in SQLite's `user_version`.
    /// 1 is the layout with failure reasons and refresh requests; 2 adds the `estimated` mark on
    /// backfilled history. Older databases are migrated in place. Raise it with every migration, never lower it.
    public static let schemaVersion = 2

    private static let incompleteFailureDelay: TimeInterval = 0.001

    private let db: OpaquePointer
    private let lock = NSRecursiveLock()

    /// Opens a local database and brings it to `schemaVersion`. Throws `CoreError.storeNewerThanBinary`,
    /// before changing anything, when the file was written by a newer build; otherwise
    /// `CoreError.storage` on failure.
    public convenience init(path: String) throws {
        try self.init(path: path, schemaVersion: Self.schemaVersion, whileMigrating: {})
    }

    /// Opens a store as a build whose layout is `schemaVersion`. `whileMigrating` runs inside the migration
    /// transaction, after the stored version is read, so a test can start a second build at that moment.
    init(path: String, schemaVersion: Int, whileMigrating: () -> Void) throws {
        try PrivateStorage.database(path)
        var connection: OpaquePointer?
        guard sqlite3_open_v2(path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let connection else {
            if let connection { sqlite3_close(connection) }
            throw CoreError.storage
        }
        db = connection
        sqlite3_busy_timeout(db, 5000)
        do {
            try migrate(to: schemaVersion, whileMigrating: whileMigrating)
            try PrivateStorage.database(path)
        } catch {
            sqlite3_close(db)
            throw error
        }
    }

    deinit { sqlite3_close(db) }

    /// Saves source windows once; missing previously observed active windows retain a failure.
    /// `estimated` points are saved in the same transaction, marked as estimates; they never count as readings.
    public func record(_ snapshot: Snapshot, estimated: [HistoryPoint] = []) throws {
        try lock.withLock {
            try execute("BEGIN IMMEDIATE")
            do {
                try insertReading(snapshot)
                for point in estimated { try insertEstimated(point, account: snapshot.account, weekReset: snapshot.sevenDay.resetsAt) }
                let retainedFive = try latestWindow(snapshot.account, weekly: false)
                let missingActiveFive = snapshot.fiveHour.pct == nil
                    && (retainedFive?.0.resetsAt ?? .distantPast) > snapshot.at
                if snapshot.sevenDay.pct != nil, !missingActiveFive {
                    try clearFailure(snapshot.account)
                } else {
                    // Stamped just after the reading: a failure only counts against readings it follows.
                    try markFailed(snapshot.account, at: snapshot.at.addingTimeInterval(Self.incompleteFailureDelay),
                        reason: .invalidOutput)
                }
                try execute("COMMIT")
            } catch {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                throw error
            }
        }
    }

    /// Reports whether the account has any real reading, so a new account can be backfilled once.
    public func hasReadings(_ account: String) throws -> Bool {
        try lock.withLock {
            let statement = try prepare("SELECT 1 FROM snapshots WHERE account = ? AND estimated = 0 LIMIT 1")
            defer { sqlite3_finalize(statement) }
            bind(account, to: statement, at: 1)
            return try row(statement)
        }
    }

    /// Returns each window's latest valid reading, with the oldest contributing timestamp.
    public func latest(_ account: String) throws -> Snapshot? {
        try lock.withLock {
            let statement = try prepare("SELECT at, plan, five_pct, five_reset, week_pct, week_reset FROM snapshots WHERE account = ? AND estimated = 0 ORDER BY at DESC LIMIT 1")
            defer { sqlite3_finalize(statement) }
            bind(account, to: statement, at: 1)
            guard try row(statement) else { return nil }
            let five = try latestWindow(account, weekly: false)
            let week = try latestWindow(account, weekly: true)
            let latest = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
            let contributing = [five, week].compactMap { reading -> Date? in
                guard let reading, (reading.0.resetsAt ?? .distantPast) > latest else { return nil }
                return reading.1
            }
            return Snapshot(account: account, at: ([latest] + contributing).min() ?? latest,
                plan: text(statement, 1), fiveHour: five?.0 ?? UsageWindow(), sevenDay: week?.0 ?? UsageWindow())
        }
    }

    /// Returns readings since the weekly start, matching the engine timestamp boundary.
    public func windowHistory(_ account: String, resetsAt: Date) throws -> [HistoryPoint] {
        try lock.withLock {
            let statement = try prepare("SELECT at, week_pct, estimated FROM snapshots WHERE account = ? AND at >= ? AND at <= ? AND week_pct IS NOT NULL ORDER BY at")
            defer { sqlite3_finalize(statement) }
            bind(account, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, resetsAt.timeIntervalSince1970 - Forecaster.week)
            sqlite3_bind_double(statement, 3, resetsAt.timeIntervalSince1970)
            var points: [HistoryPoint] = []
            while try row(statement) {
                points.append(HistoryPoint(at: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                    pct: sqlite3_column_double(statement, 1), estimated: sqlite3_column_int(statement, 2) != 0))
            }
            return points
        }
    }

    /// Persists failure state, with its safe reason, without replacing the last successful reading.
    public func markFailed(_ account: String, at: Date, reason: AccountReadError? = nil) throws {
        try lock.withLock {
            let statement = try prepare("INSERT OR REPLACE INTO failures(account, at, reason) VALUES (?, ?, ?)")
            defer { sqlite3_finalize(statement) }
            bind(account, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, at.timeIntervalSince1970)
            bind(reason?.rawValue, to: statement, at: 3)
            try finish(statement)
        }
    }

    /// Returns the safe reason of a failure recorded after `after`, so a process that did not
    /// poll can still say why an account has no fresh reading.
    public func failureReason(_ account: String, after: Date? = nil) throws -> AccountReadError? {
        try lock.withLock {
            let statement = try prepare("SELECT reason FROM failures WHERE account = ? AND at > ?")
            defer { sqlite3_finalize(statement) }
            bind(account, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, (after ?? .distantPast).timeIntervalSince1970)
            guard try row(statement) else { return nil }
            return text(statement, 0).flatMap(AccountReadError.init(rawValue:))
        }
    }

    /// Asks the process that polls to take a reading soon. Repeated requests collapse into one.
    public func requestRefresh(at: Date) throws {
        try lock.withLock {
            let statement = try prepare("INSERT OR REPLACE INTO refresh_requests(id, at) VALUES (1, ?)")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, at.timeIntervalSince1970)
            try finish(statement)
        }
    }

    /// Reports whether a process that does not poll asked for a reading.
    public func hasRefreshRequest() throws -> Bool {
        try lock.withLock {
            let statement = try prepare("SELECT 1 FROM refresh_requests WHERE id = 1")
            defer { sqlite3_finalize(statement) }
            return try row(statement)
        }
    }

    /// Removes the pending refresh request. Returns whether one was pending.
    @discardableResult
    public func takeRefreshRequest() throws -> Bool {
        try lock.withLock {
            let statement = try prepare("DELETE FROM refresh_requests WHERE id = 1")
            defer { sqlite3_finalize(statement) }
            try finish(statement)
            return sqlite3_changes(db) > 0
        }
    }

    /// A number that differs between two calls when another connection committed to the database in between.
    /// Changes made through this connection do not change it. Clients compare it to notice readings stored by another process.
    public func dataVersion() throws -> Int {
        try lock.withLock {
            let statement = try prepare("PRAGMA data_version")
            defer { sqlite3_finalize(statement) }
            guard try row(statement) else { throw CoreError.storage }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    /// Reports a source failure retained since the last successful refresh.
    public func hasFailure(_ account: String, after: Date? = nil) throws -> Bool {
        try lock.withLock {
            let statement = try prepare("SELECT 1 FROM failures WHERE account = ? AND at > ?")
            defer { sqlite3_finalize(statement) }
            bind(account, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, (after ?? .distantPast).timeIntervalSince1970)
            return try row(statement)
        }
    }

    /// Reads the stored version and brings the layout to `schemaVersion` in one write transaction, so a
    /// build that started earlier can never stamp an older version over a newer build's migration.
    private func migrate(to schemaVersion: Int, whileMigrating: () -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            let storedVersion = try userVersion()
            guard storedVersion <= schemaVersion else { throw CoreError.storeNewerThanBinary }
            whileMigrating()
            try execute("CREATE TABLE IF NOT EXISTS snapshots (account TEXT NOT NULL, at REAL NOT NULL, plan TEXT, five_pct REAL, five_reset REAL, week_pct REAL, week_reset REAL, PRIMARY KEY(account, at))")
            try execute("CREATE INDEX IF NOT EXISTS snapshots_window ON snapshots(account, week_reset, at)")
            try execute("CREATE TABLE IF NOT EXISTS failures (account TEXT PRIMARY KEY NOT NULL, at REAL NOT NULL, reason TEXT)")
            try addColumn("reason", definition: "TEXT", to: "failures")
            try addColumn("estimated", definition: "INTEGER NOT NULL DEFAULT 0", to: "snapshots")
            try execute("CREATE TABLE IF NOT EXISTS refresh_requests (id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1), at REAL NOT NULL)")
            if storedVersion < schemaVersion { try execute("PRAGMA user_version = \(schemaVersion)") }
            try execute("COMMIT")
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    private func userVersion() throws -> Int {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard try row(statement) else { throw CoreError.storage }
        return Int(sqlite3_column_int(statement, 0))
    }

    /// Older stores lack columns added later; each is added in place and never dropped.
    private func addColumn(_ name: String, definition: String, to table: String) throws {
        guard try !hasColumn(name, in: table) else { return }
        // A second process may add the column first; only a missing column afterwards is an error.
        sqlite3_exec(db, "ALTER TABLE \(table) ADD COLUMN \(name) \(definition)", nil, nil, nil)
        guard try hasColumn(name, in: table) else { throw CoreError.storage }
    }

    private func hasColumn(_ name: String, in table: String) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        while try row(statement) { if text(statement, 1) == name { return true } }
        return false
    }

    private func insertReading(_ snapshot: Snapshot) throws {
        // A real reading replaces an estimate at the same timestamp; it never replaces another real reading.
        let statement = try prepare("""
            INSERT INTO snapshots (account, at, plan, five_pct, five_reset, week_pct, week_reset) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account, at) DO UPDATE SET plan = excluded.plan, five_pct = excluded.five_pct,
                five_reset = excluded.five_reset, week_pct = excluded.week_pct, week_reset = excluded.week_reset, estimated = 0
            WHERE snapshots.estimated = 1
            """)
        defer { sqlite3_finalize(statement) }
        bind(snapshot.account, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, snapshot.at.timeIntervalSince1970)
        bind(snapshot.plan, to: statement, at: 3)
        bind(snapshot.fiveHour.pct, to: statement, at: 4)
        bind(snapshot.fiveHour.resetsAt?.timeIntervalSince1970, to: statement, at: 5)
        bind(snapshot.sevenDay.pct, to: statement, at: 6)
        bind(snapshot.sevenDay.resetsAt?.timeIntervalSince1970, to: statement, at: 7)
        try finish(statement)
    }

    private func insertEstimated(_ point: HistoryPoint, account: String, weekReset: Date?) throws {
        let statement = try prepare("INSERT OR IGNORE INTO snapshots (account, at, week_pct, week_reset, estimated) VALUES (?, ?, ?, ?, 1)")
        defer { sqlite3_finalize(statement) }
        bind(account, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, point.at.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, point.pct)
        bind(weekReset?.timeIntervalSince1970, to: statement, at: 4)
        try finish(statement)
    }

    private func clearFailure(_ account: String) throws {
        let statement = try prepare("DELETE FROM failures WHERE account = ?")
        defer { sqlite3_finalize(statement) }
        bind(account, to: statement, at: 1)
        try finish(statement)
    }

    private func latestWindow(_ account: String, weekly: Bool) throws -> (UsageWindow, Date)? {
        let query = weekly
            ? "SELECT at, week_pct, week_reset FROM snapshots WHERE account = ? AND estimated = 0 AND week_pct IS NOT NULL AND week_reset IS NOT NULL ORDER BY at DESC LIMIT 1"
            : "SELECT at, five_pct, five_reset FROM snapshots WHERE account = ? AND estimated = 0 AND five_pct IS NOT NULL AND five_reset IS NOT NULL ORDER BY at DESC LIMIT 1"
        let statement = try prepare(query)
        defer { sqlite3_finalize(statement) }
        bind(account, to: statement, at: 1)
        guard try row(statement) else { return nil }
        let window = UsageWindow(pct: number(statement, 1),
            resetsAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)))
        return (window, Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)))
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CoreError.storage }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw CoreError.storage }
        return statement
    }

    private func finish(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw CoreError.storage }
    }

    private func row(_ statement: OpaquePointer) throws -> Bool {
        let code = sqlite3_step(statement)
        guard code == SQLITE_ROW || code == SQLITE_DONE else { throw CoreError.storage }
        return code == SQLITE_ROW
    }

    private func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) {
        guard let value else { sqlite3_bind_null(statement, index); return }
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }

    private func bind(_ value: Double?, to statement: OpaquePointer, at index: Int32) {
        if let value { sqlite3_bind_double(statement, index, value) }
        else { sqlite3_bind_null(statement, index) }
    }
}

private func number(_ statement: OpaquePointer, _ index: Int32) -> Double? {
    sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
}

private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
    sqlite3_column_text(statement, index).map { String(cString: $0) }
}
