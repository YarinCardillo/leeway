import Foundation
import Darwin

/// A small HTTP/1.1 server bound exclusively to IPv4 loopback, with one request per connection.
public final class LoopbackServer: @unchecked Sendable {
    public let port: UInt16
    private let router: HTTPRouter
    private let socketFD: Int32
    private let lock = NSLock()
    private let workers = DispatchSemaphore(value: 16)
    private var isStarted = false
    private var isStopped = false

    /// Binds loopback. Port zero chooses an available port. Throws CoreError.server on socket failure.
    public init(provider: any UsageProvider, port: UInt16 = 8799) throws {
        router = HTTPRouter(provider: provider)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CoreError.server }
        do {
            self.port = try Self.bind(fd, port: port)
            socketFD = fd
        } catch { Darwin.close(fd); throw error }
    }

    deinit { stop() }

    /// Starts accepting bounded local connections. Calling this more than once has no effect.
    public func start() {
        let shouldStart = lock.withLock {
            guard !isStarted, !isStopped else { return false }
            isStarted = true
            return true
        }
        if shouldStart { DispatchQueue.global().async { self.acceptConnections() } }
    }

    /// Stops accepting new connections and releases the listening socket. Safe to repeat.
    public func stop() {
        lock.withLock {
            guard !isStopped else { return }
            isStopped = true
            shutdown(socketFD, SHUT_RDWR)
            Darwin.close(socketFD)
        }
    }

    private static func bind(_ fd: Int32, port: UInt16) throws -> UInt16 {
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let addressSize = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, addressSize) }
        }
        guard bound == 0, listen(fd, 16) == 0 else { throw CoreError.server }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard result == 0 else { throw CoreError.server }
        return UInt16(bigEndian: address.sin_port)
    }

    private func acceptConnections() {
        while !lock.withLock({ isStopped }) {
            let client = accept(socketFD, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            guard workers.wait(timeout: .now()) == .success else { Darwin.close(client); continue }
            let deadline = DispatchTime.now() + 2
            DispatchQueue.global().async { self.serve(client, deadline: deadline) }
        }
    }

    private func serve(_ client: Int32, deadline: DispatchTime) {
        var timeout = timeval(tv_sec: 2, tv_usec: 0), noSignal: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        do {
            let request = try HTTPFraming.read(client, deadline: deadline)
            Task { self.finish(await router.handle(request), client: client) }
        } catch let error as HTTPParseError { finish(router.error(error.code, "invalid HTTP request"), client: client) }
        catch { finish(router.error(400, "invalid HTTP request"), client: client) }
    }

    private func finish(_ response: HTTPResponse, client: Int32) {
        DispatchQueue.global().async {
            defer { Darwin.close(client); self.workers.signal() }
            HTTPFraming.write(response, to: client)
        }
    }
}
