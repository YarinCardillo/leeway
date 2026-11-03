import Darwin
import Foundation

/// Dispatch handles termination outside the signal handler, where process cleanup is safe.
final class ShutdownSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [DispatchSourceSignal] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReceived = false

    init() {
        for value in [SIGINT, SIGTERM] {
            signal(value, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: value, queue: .global())
            source.setEventHandler { [weak self] in self?.receive() }
            sources.append(source)
            source.resume()
        }
    }

    deinit { for source in sources { source.cancel() } }

    func wait() async {
        await withCheckedContinuation { pending in
            lock.withLock {
                if isReceived { pending.resume() }
                else { continuation = pending }
            }
        }
    }

    private func receive() {
        let pending = lock.withLock {
            isReceived = true
            let pending = continuation
            continuation = nil
            return pending
        }
        pending?.resume()
    }
}
