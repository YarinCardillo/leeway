import Darwin
import Foundation

/// Observes policy contents and the containing directory, including atomic replacements.
public enum PolicyChanges {
    /// Emits validated intervals on file changes, without periodic filesystem wakeups.
    /// Creates a missing policy directory; cancelling consumption closes all descriptors.
    public static func watch(file: URL, home: URL) throws -> AsyncStream<Int> {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let initial = try Policy.load(file, home: home).pollMinutes
        let descriptor = open(file.deletingLastPathComponent().path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw CoreError.storage }
        let (stream, send) = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let watch = PolicyWatch(descriptor: descriptor, file: file, home: home, initial: initial, send: send)
        send.onTermination = { _ in watch.stop() }
        watch.start()
        return stream
    }
}

/// The serial queue owns mutable watch state; cancellation is safe from any executor.
private final class PolicyWatch: @unchecked Sendable {
    private let queue = DispatchQueue(label: "leeway.policy-changes")
    private let directory: any DispatchSourceFileSystemObject
    private var contents: (any DispatchSourceFileSystemObject)?
    private let file: URL
    private let home: URL
    private let send: AsyncStream<Int>.Continuation
    private var lastMinutes: Int

    init(descriptor: Int32, file: URL, home: URL, initial: Int, send: AsyncStream<Int>.Continuation) {
        self.file = file; self.home = home; self.send = send; lastMinutes = initial
        directory = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete], queue: queue)
        directory.setCancelHandler { close(descriptor) }
    }

    func start() {
        queue.sync {
            directory.setEventHandler { [weak self] in self?.reload() }
            rearmContents()
            send.yield(lastMinutes)
            directory.resume()
            reload()
        }
    }

    func stop() {
        queue.async {
            self.contents?.cancel()
            self.contents = nil
            self.directory.cancel()
        }
    }

    private func rearmContents() {
        contents?.cancel()
        contents = nil
        let descriptor = open(file.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { close(descriptor) }
        contents = source
        source.resume()
    }

    private func reload() {
        rearmContents()
        do {
            let minutes = try Policy.load(file, home: home).pollMinutes
            guard minutes != lastMinutes else { return }
            lastMinutes = minutes
            send.yield(minutes)
        } catch { FileHandle.standardError.write(Data("invalid policy update; keeping the last valid policy\n".utf8)) }
    }
}
