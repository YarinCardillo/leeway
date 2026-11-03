import Foundation
import Testing
@testable import LeewayCore

@Test func launchOptionsResolveExplicitHomeAndPolicyWithoutChangingCommand() throws {
    let options = try LaunchOptions.parse(["--home", "/example", "status", "--json", "--policy", "~/rules.toml"],
        defaultHome: URL(fileURLWithPath: "/default"))
    #expect(options.home.path == "/example")
    #expect(options.policyFile.path == "/example/rules.toml")
    #expect(options.arguments == ["status", "--json"])
}

actor FailingTickProvider: UsageProvider {
    private(set) var ticks = 0
    func status(refresh: Bool) async throws -> StatusDocument {
        ticks += 1
        if ticks == 1 { throw CoreError.storage }
        return StatusDocument(generatedAt: now)
    }
    func advise(_ request: AdviceRequest) async throws -> Advice { Advice(verdict: .go, reason: "fixture") }
}

actor TickWaiter {
    private var calls = 0
    func wait(_ seconds: TimeInterval) throws {
        calls += 1
        #expect(seconds == 300)
        if calls == 2 { throw CancellationError() }
    }
}

@Test func pollingSurvivesFailedTickAndRetriesAtConfiguredInterval() async throws {
    let provider = FailingTickProvider(), waiter = TickWaiter()
    await PollingLoop.run(provider: provider, minutes: 5, clock: { now }, wait: { try await waiter.wait($0) }, onError: { _ in })
    #expect(await provider.ticks == 2)
}
