import Foundation
import Testing
@testable import LeewayCore

@Test func loopbackTransportServesJSONAndRejectsForeignHost() async throws {
    let server = try LoopbackServer(provider: FixtureProvider(), port: 0)
    server.start()
    defer { server.stop() }
    let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/v1/status"))
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 3
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let (data, response) = try await session.data(from: url)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(try JSONCodec.decoder().decode(StatusDocument.self, from: data).accounts.first?.id == "first")
    var foreign = URLRequest(url: url)
    foreign.setValue("evil.example:8799", forHTTPHeaderField: "Host")
    let (_, denied) = try await session.data(for: foreign)
    #expect((denied as? HTTPURLResponse)?.statusCode == 403)
}

@Test(arguments: ["GET /v1/status HTTP/1.1\r\nHost: localhost:8799\r\nHost: other:8799",
    "POST /v1/advise HTTP/1.1\r\nHost: localhost:8799\r\nContent-Length: -1",
    "POST /v1/advise HTTP/1.1\r\nHost: localhost:8799\r\nTransfer-Encoding: chunked"])
func httpFramingRejectsAmbiguousHeaders(_ head: String) {
    #expect(throws: HTTPParseError.self) { try HTTPFraming.parseHead(head) }
}
