import Foundation

/// Blocking provider access runs on a dispatch worker, outside the service actor and Swift executor.
struct SourceReadings: Sendable {
    let home: URL
    let runner: any ProcessRunner
    let environment: [String: String]
    let clock: @Sendable () -> Date

    func read(_ targets: [Target]) async -> [(String, [Snapshot], AccountReadError?)] {
        let cancellation = ReadingCancellation()
        return await withTaskCancellationHandler {
            await read(targets, cancellation: cancellation)
        } onCancel: { cancellation.cancel() }
    }

    private func read(_ targets: [Target], cancellation: ReadingCancellation) async -> [(String, [Snapshot], AccountReadError?)] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let readings = targets.map { target -> (String, [Snapshot], AccountReadError?) in
                    guard !cancellation.isCancelled else { return (target.id, [], nil) }
                    do {
                        if target.provider == .codex {
                            let history = try CodexReader.history(home: target.configDir, account: target.id)
                            return (target.id, history, history.isEmpty ? .invalidOutput : nil)
                        }
                        let snapshot = try ClaudeReader(runner: runner, home: home, environment: environment, clock: clock,
                            isCancelled: { cancellation.isCancelled }).read(target)
                        return (target.id, snapshot.map { [$0] } ?? [], snapshot == nil ? .invalidOutput : nil)
                    } catch { return (target.id, [], (error as? AccountReadError) ?? .invalidOutput) }
                }
                continuation.resume(returning: readings)
            }
        }
    }
}

private final class ReadingCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}
