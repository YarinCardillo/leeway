import Darwin
import Foundation

/// Serializes spawn/registration against shutdown so no newly launched group can escape it.
final class ProcessGroups: @unchecked Sendable {
    private let lock = NSLock()
    private var groups: Set<pid_t> = []
    private var isStopped = false

    func launch(_ spawn: () throws -> pid_t) throws -> pid_t {
        try lock.withLock {
            guard !isStopped else { throw CancellationError() }
            let pid = try spawn()
            groups.insert(pid)
            return pid
        }
    }

    func finish(_ pid: pid_t) {
        terminate([pid])
        _ = lock.withLock { groups.remove(pid) }
    }

    func shutdown() {
        let active = lock.withLock { isStopped = true; return groups }
        terminate(active)
    }

    private func terminate(_ active: Set<pid_t>) {
        for pid in active { kill(-pid, SIGTERM) }
        wait(active, seconds: 0.25)
        for pid in active where kill(-pid, 0) == 0 { kill(-pid, SIGKILL) }
        wait(active, seconds: 0.5)
    }

    private func wait(_ active: Set<pid_t>, seconds: Double) {
        let deadline = DispatchTime.now() + seconds
        while DispatchTime.now() < deadline && active.contains(where: { kill(-$0, 0) == 0 }) { usleep(10_000) }
    }
}
