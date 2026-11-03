import Foundation
import Testing
@testable import LeewayCore

struct FixtureProvider: UsageProvider {
    func status(refresh: Bool) async throws -> StatusDocument { StatusDocument(generatedAt: now, accounts: [account("first")]) }
    func advise(_ request: AdviceRequest) async throws -> Advice { ask([account("first")], role: request.role, agent: request.agent) }
}

@Test func httpStatusAndAdviceReturnVersionedContracts() async throws {
    let router = HTTPRouter(provider: FixtureProvider())
    let status = await router.handle(HTTPRequest(method: "GET", path: "/v1/status", headers: ["host": "127.0.0.1:8799"]))
    #expect(status.status == 200)
    #expect(try JSONCodec.decoder().decode(StatusDocument.self, from: status.body).schemaVersion == 3)
    let body = Data("{\"repo\":\"/example\",\"role\":\"builder\",\"task_class\":\"integration\",\"agent\":\"claude\"}".utf8)
    let response = await router.handle(HTTPRequest(method: "POST", path: "/v1/advise", headers: ["host": "localhost:8799"], body: body))
    #expect(response.status == 200)
    #expect(try JSONCodec.decoder().decode(Advice.self, from: response.body).verdict == .go)
}

@Test(arguments: [["host": "evil.example:8799"], ["host": "127.0.0.1:8799", "origin": "https://evil.example"], [:]])
func httpRejectsBrowserAndRebindingRequests(_ headers: [String: String]) async {
    let router = HTTPRouter(provider: FixtureProvider())
    #expect(await router.handle(HTTPRequest(method: "GET", path: "/v1/status", headers: headers)).status == 403)
}

@Test(arguments: ["no JSON", "[]", "{}", "{\"repo\":\"\",\"role\":\"builder\",\"task_class\":\"design\"}",
    "{\"repo\":\"/x\",\"role\":\"boss\",\"task_class\":\"design\"}",
    "{\"repo\":\"/x\",\"role\":\"builder\",\"task_class\":\"design\",\"extra\":1}"])
func httpRejectsMalformedAdvice(_ text: String) async {
    let router = HTTPRouter(provider: FixtureProvider())
    let result = await router.handle(HTTPRequest(method: "POST", path: "/v1/advise", headers: ["host": "127.0.0.1:8799"], body: Data(text.utf8)))
    #expect(result.status == 400)
}

@Test func httpBoundsBodiesAndDoesNotRefreshOnGet() async {
    let router = HTTPRouter(provider: FixtureProvider())
    let oversized = HTTPRequest(method: "POST", path: "/v1/advise", headers: ["host": "127.0.0.1:8799"], body: Data(repeating: 32, count: 8193))
    #expect(await router.handle(oversized).status == 413)
    #expect(await router.handle(HTTPRequest(method: "GET", path: "/v1/refresh", headers: ["host": "127.0.0.1:8799"])).status == 404)
}
