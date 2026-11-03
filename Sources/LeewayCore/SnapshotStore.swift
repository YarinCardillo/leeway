import Foundation
import CSQLite

/// Serialized, transactional snapshot storage. Errors never include database paths or data.
public final class SnapshotStore: @unchecked Sendable {
    private let db: OpaquePointer
    private let lock = NSRecursiveLock()

    /// Opens a local database and initializes the v1 schema. Throws CoreError.storage on failure.
    public init(path: String) throws {
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
            try execute("CREATE TABLE IF NOT EXISTS snapshots (account TEXT NOT NULL, at REAL NOT NULL, plan TEXT, five_pct REAL, five_reset REAL, week_pct REAL, week_reset REAL, PRIMARY KEY(account, at))")
            try execute("CREATE INDEX IF NOT EXISTS snapshots_window ON snapshots(account, week_reset, at)")
            try execute("CREATE TABLE IF NOT EXISTS failures (account TEXT PRIMARY KEY NOT NULL, at REAL NOT NULL)")
            try PrivateStorage.database(path)
        } catch {
            sqlite3_close(db)
            throw error
        }
    }

    deinit { sqlite3_close(db) }

    /// Saves source windows once; missing previously observed active windows retain a failure.
    public func record(_ snapshot: Snapshot) throws {
        try lock.withLock {
            try execute("BEGIN IMMEDIATE")
            do {
                let statement = try prepare("INSERT OR IGNORE INTO snapshots (account, at, plan, five_pct, five_reset, week_pct, week_reset) VALUES (?, ?, ?, ?, ?, ?, ?)")
                defer { sqlite3_finalize(statement) }
                bind(snapshot.account, to: statement, at: 1)
                sqlite3_bind_double(statement, 2, snapshot.at.timeIntervalSince1970)
                bind(snapshot.plan, to: statement, at: 3)
                bind(snapshot.fiveHour.pct, to: statement, at: 4)
                bind(snapshot.fiveHour.resetsAt?.timeIntervalSince1970, to: statement, at: 5)
                bind(snapshot.sevenDay.pct, to: statement, at: 6)
                bind(snapshot.sevenDay.resetsAt?.timeIntervalSince1970, to: statement, at: 7)
                try finish(statement)
                let retainedFive = try latestWindow(snapshot.account, weekly: false)
                let missingActiveFive = snapshot.fiveHour.pct == nil
                    && (retainedFive?.0.resetsAt ?? .distantPast) > snapshot.at
                if snapshot.sevenDay.pct != nil, !missingActiveFive {
                    try clearFailure(snapshot.account)
                } else { try markFailed(snapshot.account, at: snapshot.at) }
                try execute("COMMIT")
            } catch {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                throw error
            }
        }
    }

    /// Returns each window's latest valid reading, with the oldest contributing timestamp.
    public func latest(_ account: String) throws -> Snapshot? {
        try lock.withLock {
            let statement = try prepare("SELECT at, plan, five_pct, five_reset, week_pct, week_reset FROM snapshots WHERE account = ? ORDER BY at DESC LIMIT 1")
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
            let statement = try prepare("SELECT at, week_pct FROM snapshots WHERE account = ? AND at >= ? AND at <= ? AND week_pct IS NOT NULL ORDER BY at")
            defer { sqlite3_finalize(statement) }
            bind(account, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, resetsAt.timeIntervalSince1970 - Forecaster.week)
            sqlite3_bind_double(statement, 3, resetsAt.timeIntervalSince1970)
            var points: [HistoryPoint] = []
            while try row(statement) {
                points.append(HistoryPoint(at: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                    pct: sqlite3_column_double(statement, 1)))
            }
            return points
        }
    }

    /// Persists failure state without replacing the last successful reading.
    public func markFailed(_ account: String, at: Date) throws {
        try lock.withLock {
            let statement = try prepare("INSERT OR REPLACE INTO failures(account, at) VALUES (?, ?)")
            defer { sqlite3_finalize(statement) }
            bind(account, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, at.timeIntervalSince1970)
            try finish(statement)
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

    private func clearFailure(_ account: String) throws {
        let statement = try prepare("DELETE FROM failures WHERE account = ?")
        defer { sqlite3_finalize(statement) }
        bind(account, to: statement, at: 1)
        try finish(statement)
    }

    private func latestWindow(_ account: String, weekly: Bool) throws -> (UsageWindow, Date)? {
        let query = weekly
            ? "SELECT at, week_pct, week_reset FROM snapshots WHERE account = ? AND week_pct IS NOT NULL AND week_reset IS NOT NULL ORDER BY at DESC LIMIT 1"
            : "SELECT at, five_pct, five_reset FROM snapshots WHERE account = ? AND five_pct IS NOT NULL AND five_reset IS NOT NULL ORDER BY at DESC LIMIT 1"
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
