import Foundation
import Darwin

public struct SystemProcessRunner: ProcessRunner {
    private let groups = ProcessGroups()
    public init() {}

    /// Terminates all owned process groups with bounded escalation and rejects subsequent launches.
    public func shutdown() { groups.shutdown() }

    /// Runs an argument vector with closed stdin, bounded output, and a private process group.
    /// Launch failure and timeout use 127 and 124, with no process output on timeout.
    public func run(_ request: ProcessRequest) throws -> ProcessOutput {
        let pipe = Pipe()
        let pid: pid_t
        do { pid = try groups.launch { try spawn(request, stdout: pipe.fileHandleForWriting.fileDescriptor) } }
        catch is CancellationError { throw CancellationError() }
        catch {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            return ProcessOutput(exitCode: 127, stdout: "")
        }
        defer { groups.finish(pid) }
        return try capture(pid, pipe: pipe, request: request)
    }

    private func capture(_ pid: pid_t, pipe: Pipe, request: ProcessRequest) throws -> ProcessOutput {
        let finished = DispatchSemaphore(value: 0), drained = DispatchGroup()
        let output = ProcessCapture(), state = ProcessExit()
        try? pipe.fileHandleForWriting.close()
        drained.enter()
        DispatchQueue.global().async { output.drain(pipe.fileHandleForReading); drained.leave() }
        DispatchQueue.global().async { state.reap(pid); finished.signal() }
        let timedOut = wait(pid, request: request, finished: finished)
        guard drained.wait(timeout: .now() + 1) == .success else {
            kill(-pid, SIGKILL)
            _ = drained.wait(timeout: .now() + 1)
            return ProcessOutput(exitCode: 124, stdout: "")
        }
        try checkCancellation(request)
        return ProcessOutput(exitCode: timedOut ? 124 : state.code, stdout: timedOut ? "" : output.string)
    }

    private func wait(_ pid: pid_t, request: ProcessRequest, finished: DispatchSemaphore) -> Bool {
        let deadline = DispatchTime.now() + max(request.timeout, 0)
        while finished.wait(timeout: min(deadline, .now() + 0.05)) == .timedOut {
            if request.isCancelled() || DispatchTime.now() >= deadline {
                stopGroup(pid, finished: finished)
                return !request.isCancelled()
            }
        }
        return false
    }

    private func checkCancellation(_ request: ProcessRequest) throws {
        if request.isCancelled() { throw CancellationError() }
    }

    private func spawn(_ request: ProcessRequest, stdout: Int32) throws -> pid_t {
        try checkCancellation(request)
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw CoreError.process }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw CoreError.process }
        defer { posix_spawnattr_destroy(&attributes) }
        try configure(&actions, attributes: &attributes, request: request, stdout: stdout)
        let executable = request.executable.contains("/") ? request.executable : "/usr/bin/env"
        let arguments = [executable] + (request.executable.contains("/") ? [] : [request.executable]) + request.arguments
        return try withCStrings(arguments) { argv in
            try withCStrings(request.environment.map { $0.key + "=" + $0.value }) { env in
                var pid: pid_t = 0
                guard posix_spawn(&pid, executable, &actions, &attributes, argv, env) == 0 else { throw CoreError.process }
                return pid
            }
        }
    }

    private func configure(_ actions: inout posix_spawn_file_actions_t?, attributes: inout posix_spawnattr_t?,
        request: ProcessRequest, stdout: Int32) throws {
        let flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        var defaults = sigset_t(), mask = sigset_t()
        sigemptyset(&defaults); sigemptyset(&mask)
        for value in [SIGINT, SIGTERM, SIGHUP, SIGPIPE] { sigaddset(&defaults, value) }
        guard posix_spawnattr_setflags(&attributes, flags) == 0,
              posix_spawnattr_setsigdefault(&attributes, &defaults) == 0,
              posix_spawnattr_setsigmask(&attributes, &mask) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) == 0,
              posix_spawn_file_actions_adddup2(&actions, stdout, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_addchdir_np(&actions, request.workingDirectory.path) == 0 else { throw CoreError.process }
    }

    private func stopGroup(_ pid: pid_t, finished: DispatchSemaphore) {
        kill(-pid, SIGTERM)
        _ = finished.wait(timeout: .now() + 0.5)
        // The direct child exiting does not imply that its descendants have closed stdout.
        kill(-pid, SIGKILL)
        _ = finished.wait(timeout: .now() + 0.5)
    }

    private func withCStrings<T>(_ strings: [String], body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) throws -> T) rethrows -> T {
        let pointers = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }
        return try pointers.withUnsafeBufferPointer { try body($0.baseAddress!) }
    }
}

private final class ProcessExit: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Int32 = 127
    var code: Int32 { lock.withLock { result } }

    func reap(_ pid: pid_t) {
        var status: Int32 = 0
        var found: pid_t
        repeat { found = waitpid(pid, &status, 0) } while found < 0 && errno == EINTR
        let exit = found < 0 ? 127 : ((status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f))
        lock.withLock { result = exit }
    }
}

private final class ProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit = 4 * 1024 * 1024
    var string: String { lock.withLock { String(decoding: data, as: UTF8.self) } }

    func drain(_ handle: FileHandle) {
        defer { try? handle.close() }
        while true {
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { return }
            lock.withLock {
                if data.count < limit { data.append(chunk.prefix(limit - data.count)) }
            }
        }
    }
}
