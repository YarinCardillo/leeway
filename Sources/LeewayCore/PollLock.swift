import Darwin
import Foundation

/// An advisory lock that lets exactly one process poll quota at a time.
///
/// The lock is an `flock` on a private file, so the system releases it when the holder exits or
/// crashes. A process that does not hold it serves readings from the shared store and tries again
/// at its next round. Each instance owns its own file descriptor, so two instances on one path
/// exclude each other even inside a single process.
public final class PollLock: @unchecked Sendable {
    private let path: String
    private let guardLock = NSLock()
    private var descriptor: Int32 = -1
    private var hasReportedFailure = false

    /// - Parameter path: Lock file, usually `poll.lock` beside the history database.
    public init(path: String) { self.path = path }

    deinit { if descriptor >= 0 { close(descriptor) } }

    /// Whether this instance currently holds the lock.
    public var isHolding: Bool { guardLock.withLock { descriptor >= 0 } }

    /// Takes the lock without waiting. Returns true when this instance holds it afterwards.
    /// Returns false when another holder exists or the lock file cannot be opened.
    public func tryAcquire() -> Bool {
        guardLock.withLock {
            if descriptor >= 0 { return true }
            guard let candidate = openLockFile() else { return false }
            guard flock(candidate, LOCK_EX | LOCK_NB) == 0 else { close(candidate); return false }
            descriptor = candidate
            return true
        }
    }

    /// Lets go of the lock. Safe to call when it is not held.
    public func release() {
        guardLock.withLock {
            guard descriptor >= 0 else { return }
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }
    }

    /// Reports whether another holder exists, without keeping the lock for this instance.
    public func isHeldElsewhere() -> Bool {
        guardLock.withLock {
            if descriptor >= 0 { return false }
            guard let probe = openLockFile() else { return false }
            defer { close(probe) }
            guard flock(probe, LOCK_EX | LOCK_NB) == 0 else { return true }
            flock(probe, LOCK_UN)
            return false
        }
    }

    private func openLockFile() -> Int32? {
        do { try PrivateStorage.file(URL(fileURLWithPath: path), create: true) }
        catch { reportUnavailable(); return nil }
        let opened = open(path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard opened >= 0 else { reportUnavailable(); return nil }
        return opened
    }

    private func reportUnavailable() {
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        FileHandle.standardError.write(Data("poll lock unavailable; this process will not poll\n".utf8))
    }
}
