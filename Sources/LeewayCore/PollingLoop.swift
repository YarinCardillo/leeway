import Foundation

public enum PollingLoop {
    private enum Event: Sendable { case interval(Int), deadline(Int), stop }

    /// Refreshes immediately, then waits on cancellable deadlines and validated policy changes.
    public static func run(provider: any UsageProvider, minutes: Int,
        changes: AsyncStream<Int>? = nil,
        clock: @Sendable () -> Date = Date.init,
        wait: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        onError: @Sendable (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }) async {
        guard [5, 10, 15, 30].contains(minutes) else { onError("invalid polling interval"); return }
        let (events, send) = AsyncStream<Event>.makeStream()
        let updates = Task { if let changes { for await value in changes { send.yield(.interval(value)) } } }
        await refresh(provider, onError: onError)
        await deadlines(events, send: send, provider: provider, minutes: minutes,
                        clock: clock, wait: wait, onError: onError)
        updates.cancel(); send.finish()
        await updates.value
    }

    private static func deadlines(_ events: AsyncStream<Event>, send: AsyncStream<Event>.Continuation,
        provider: any UsageProvider, minutes: Int, clock: @Sendable () -> Date,
        wait: @escaping @Sendable (TimeInterval) async throws -> Void,
        onError: @Sendable (String) -> Void) async {
        var current = minutes, generation = 0, lastRefresh = clock()
        var deadline = schedule(Double(current * 60), generation: generation, send: send, wait: wait)
        loop: for await event in events {
            if Task.isCancelled { break }
            switch event {
            case .interval(let value):
                guard [5, 10, 15, 30].contains(value), value != current else { continue }
                current = value
            case .deadline(let token):
                guard token == generation else { continue }
                await refresh(provider, onError: onError)
                lastRefresh = clock()
            case .stop: break loop
            }
            deadline.cancel()
            await deadline.value
            generation += 1
            let remaining = max(0, Double(current * 60) - max(0, clock().timeIntervalSince(lastRefresh)))
            deadline = schedule(remaining, generation: generation, send: send, wait: wait)
        }
        deadline.cancel()
        await deadline.value
    }

    private static func refresh(_ provider: any UsageProvider, onError: @Sendable (String) -> Void) async {
        do { _ = try await provider.status(refresh: true) }
        catch { if !Task.isCancelled { onError("quota refresh failed; retrying at the next interval") } }
    }

    private static func schedule(_ seconds: TimeInterval, generation: Int,
        send: AsyncStream<Event>.Continuation,
        wait: @escaping @Sendable (TimeInterval) async throws -> Void) -> Task<Void, Never> {
        Task {
            do {
                try await wait(seconds)
                try Task.checkCancellation()
                send.yield(.deadline(generation))
            } catch { if !Task.isCancelled { send.yield(.stop) } }
        }
    }
}
