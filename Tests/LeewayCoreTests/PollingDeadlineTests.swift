import Foundation
import Testing
@testable import LeewayCore

private final class DeadlineWait: @unchecked Sendable {
    let durations: AsyncStream<TimeInterval>
    private let continuation: AsyncStream<TimeInterval>.Continuation
    private let lock = NSLock()
    private var cancellations = 0
    var cancelled: Int { lock.withLock { cancellations } }
    init() { (durations, continuation) = AsyncStream.makeStream() }
    func wait(_ seconds: TimeInterval) async throws {
        continuation.yield(seconds)
        do { try await Task.sleep(for: .seconds(3600)) }
        catch { lock.withLock { cancellations += 1 }; throw error }
    }
}

@Test(.timeLimit(.minutes(1))) func pollingPolicyChange_CancelsAndReschedulesFullDeadline() async throws {
    let provider = FailingTickProvider(), waiter = DeadlineWait()
    let (changes, send) = AsyncStream<Int>.makeStream()
    let polling = Task {
        await PollingLoop.run(provider: provider, minutes: 15, changes: changes, clock: { now },
                              wait: { try await waiter.wait($0) }, onError: { _ in })
    }
    var waits = waiter.durations.makeAsyncIterator()
    #expect(await waits.next() == 900)
    send.yield(15)
    send.yield(1)
    send.yield(5)
    #expect(await waits.next() == 300)
    #expect(waiter.cancelled == 1)
    #expect(await provider.ticks == 1)
    polling.cancel()
    await polling.value
    #expect(waiter.cancelled == 2)
}

@Test(.timeLimit(.minutes(1))) func policyWatch_SeesAtomicSavesAndKeepsLastValidInterval() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let file = home.appendingPathComponent("config/policy.toml")
    let updates = try PolicyChanges.watch(file: file, home: home)
    var changes = updates.makeAsyncIterator()
    #expect(await changes.next() == 15)
    try "poll_minutes = 5\n".write(to: file, atomically: true, encoding: .utf8)
    #expect(await changes.next() == 5)
    try "poll_minutes = 1\n".write(to: file, atomically: true, encoding: .utf8)
    try "poll_minutes = 30\n".write(to: file, atomically: true, encoding: .utf8)
    #expect(await changes.next() == 30)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: Data("poll_minutes = 10\n".utf8))
    try handle.close()
    #expect(await nextInterval(updates) == 10)
}

private func nextInterval(_ changes: AsyncStream<Int>) async -> Int? {
    await withTaskGroup(of: Int?.self) { group in
        group.addTask { for await value in changes { return value }; return nil }
        group.addTask { try? await Task.sleep(for: .seconds(2)); return nil }
        let value = await group.next() ?? nil
        group.cancelAll()
        return value
    }
}

@Test func policyWatch_SeesInPlaceEditsOfExistingFile() async throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let file = home.appendingPathComponent("policy.toml")
    try "poll_minutes = 15\n".write(to: file, atomically: true, encoding: .utf8)
    let updates = try PolicyChanges.watch(file: file, home: home)
    var changes = updates.makeAsyncIterator()
    #expect(await changes.next() == 15)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: Data("poll_minutes = 5\n".utf8))
    try handle.close()
    #expect(await nextInterval(updates) == 5)
}
