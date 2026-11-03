import Foundation
import Darwin

struct HTTPParseError: Error { let code: Int }

enum HTTPFraming {
    private static let headerLimit = 16 * 1024
    private static let delimiter = Data("\r\n\r\n".utf8)

    static func parseHead(_ text: String) throws -> (String, String, [String: String], Int) {
        let lines = text.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: false)
        guard first.count == 3, first[2] == "HTTP/1.1", first[1].hasPrefix("/") else { throw HTTPParseError(code: 400) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw HTTPParseError(code: 400) }
            let key = String(line[..<colon]).lowercased()
            guard !key.isEmpty, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  headers[key] == nil else { throw HTTPParseError(code: 400) }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil else { throw HTTPParseError(code: 400) }
        let rawLength = headers["content-length"] ?? "0"
        guard !rawLength.isEmpty, rawLength.allSatisfy({ $0.isASCII && $0.isNumber }), let length = Int(rawLength) else {
            throw HTTPParseError(code: 400)
        }
        guard length <= HTTPRouter.maxBodyBytes else { throw HTTPParseError(code: 413) }
        return (String(first[0]), String(first[1]), headers, length)
    }

    static func read(_ fd: Int32, deadline: DispatchTime = .now() + 2) throws -> HTTPRequest {
        var data = Data()
        while data.range(of: delimiter) == nil {
            data.append(try receive(fd, deadline: deadline))
            if data.count > headerLimit + HTTPRouter.maxBodyBytes { throw HTTPParseError(code: 413) }
        }
        guard let boundary = data.range(of: delimiter), boundary.lowerBound <= headerLimit,
              let head = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { throw HTTPParseError(code: 400) }
        let (method, path, headers, length) = try parseHead(head)
        var body = Data(data[boundary.upperBound...])
        while body.count < length { body.append(try receive(fd, deadline: deadline)) }
        guard body.count == length else { throw HTTPParseError(code: 400) }
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    static func write(_ response: HTTPResponse, to fd: Int32) {
        let header = "HTTP/1.1 \(response.status) \(reason(response.status))\r\nContent-Type: application/json\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        let data = Data(header.utf8) + response.body
        data.withUnsafeBytes { buffer in
            guard let start = buffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let count = send(fd, start.advanced(by: sent), data.count - sent, 0)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return }
                sent += count
            }
        }
    }

    private static func receive(_ fd: Int32, deadline: DispatchTime) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard deadline.uptimeNanoseconds > now else { throw HTTPParseError(code: 400) }
            let remaining = deadline.uptimeNanoseconds - now
            var timeout = timeval(tv_sec: Int(remaining / 1_000_000_000),
                tv_usec: suseconds_t(max(1, (remaining % 1_000_000_000) / 1000)))
            guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0 else {
                throw HTTPParseError(code: 400)
            }
            let count = recv(fd, &bytes, bytes.count, 0)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw HTTPParseError(code: 400) }
            return Data(bytes.prefix(count))
        }
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 413: "Payload Too Large"
        default: "Internal Server Error"
        }
    }
}
