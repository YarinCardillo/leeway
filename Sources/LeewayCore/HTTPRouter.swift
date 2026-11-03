import Foundation

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data
    public init(method: String, path: String, headers: [String: String], body: Data = Data()) {
        self.method = method; self.path = path
        self.headers = headers.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) { self.status = status; self.body = body }
}

public struct HTTPRouter: Sendable {
    private let provider: any UsageProvider
    public init(provider: any UsageProvider) { self.provider = provider }
    /// Routes local requests. Source reads and error details remain behind the provider boundary.
    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        guard isLocal(request) else { return error(403, "forbidden") }
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        do {
            switch (request.method, path) {
            case ("GET", "/v1/status"): return try response(await provider.status(refresh: false))
            case ("POST", "/v1/refresh"): return try response(await provider.status(refresh: true))
            case ("POST", "/v1/advise"):
                guard request.body.count <= Self.maxBodyBytes else { return error(413, "body too large") }
                let advice = try AdviceRequest.parse(request.body)
                return try response(await provider.advise(advice))
            default: return error(404, "not found")
            }
        } catch CoreError.invalidRequest(let message) { return error(400, message) }
        catch { return self.error(500, "service unavailable") }
    }

    static let maxBodyBytes = 8192

    private func isLocal(_ request: HTTPRequest) -> Bool {
        guard request.headers["origin"] == nil, let host = request.headers["host"],
              let separator = host.lastIndex(of: ":"), let port = Int(host[host.index(after: separator)...]),
              (1...65535).contains(port) else { return false }
        return ["127.0.0.1", "localhost"].contains(String(host[..<separator]))
    }

    private func response<T: Encodable>(_ value: T) throws -> HTTPResponse {
        HTTPResponse(status: 200, body: try JSONCodec.encoder().encode(value))
    }

    func error(_ status: Int, _ message: String) -> HTTPResponse {
        struct Payload: Encodable { let schemaVersion = 1; let error: String }
        let body = (try? JSONCodec.encoder().encode(Payload(error: message))) ?? Data("{\"schema_version\":1,\"error\":\"service unavailable\"}".utf8)
        return HTTPResponse(status: status, body: body)
    }
}

extension AdviceRequest {
    /// Validates the complete v1 request boundary. Invalid inputs throw a safe CoreError.invalidRequest.
    public static func parse(_ body: Data) throws -> AdviceRequest {
        guard let raw = jsonObject(body), Set(raw.keys).isSubset(of: ["repo", "role", "task_class", "agent", "account"]),
              let result = try? JSONCodec.decoder().decode(AdviceRequest.self, from: body),
              !result.repo.isEmpty, result.account == nil || result.account?.isEmpty == false else {
            throw CoreError.invalidRequest("body must contain a valid repo, role, task_class, agent, and account")
        }
        return result
    }
}
