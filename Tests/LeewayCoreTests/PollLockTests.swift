import Darwin
import Foundation
import Testing
@testable import LeewayCore

private func lockPath() throws -> String {
    try temporaryDirectory().appendingPathComponent("poll.lock").path
}

@Test func pollLock_SecondHolderOnSamePath_IsRefusedUntilFirstReleases() throws {
    let path = try lockPath()
    let first = PollLock(path: path), second = PollLock(path: path)
    #expect(first.tryAcquire())
    #expect(!second.tryAcquire())
    #expect(second.isHeldElsewhere())
    first.release()
    #expect(!second.isHeldElsewhere())
    #expect(second.tryAcquire())
    #expect(!first.tryAcquire())
}

@Test func pollLock_AcquireTwice_StaysHeldAndReleaseIsIdempotent() throws {
    let lock = PollLock(path: try lockPath())
    #expect(lock.tryAcquire())
    #expect(lock.tryAcquire())
    #expect(lock.isHolding)
    lock.release()
    lock.release()
    #expect(!lock.isHolding)
}

@Test func pollLock_Probe_DoesNotTakeTheLock() throws {
    let path = try lockPath()
    let probing = PollLock(path: path), other = PollLock(path: path)
    #expect(!probing.isHeldElsewhere())
    #expect(!probing.isHolding)
    #expect(other.tryAcquire())
}

@Test func pollLock_DroppedHolder_ReleasesTheLock() throws {
    let path = try lockPath()
    var holder: PollLock? = PollLock(path: path)
    #expect(holder?.tryAcquire() == true)
    holder = nil
    #expect(PollLock(path: path).tryAcquire())
}

@Test func pollLock_UnwritablePath_DoesNotAcquire() {
    let lock = PollLock(path: "/nonexistent-leeway-test-root/poll.lock")
    #expect(!lock.tryAcquire())
    #expect(!lock.isHolding)
}

@Test func pollLock_File_IsOwnerOnly() throws {
    let path = try lockPath()
    let lock = PollLock(path: path)
    #expect(lock.tryAcquire())
    var info = stat()
    #expect(stat(path, &info) == 0)
    #expect(info.st_mode & 0o777 == 0o600)
}
