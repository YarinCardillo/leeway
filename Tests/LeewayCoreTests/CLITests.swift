import Foundation
import Testing
@testable import LeewayCore

@Test func cliStatusJsonAndTextUseSharedContract() async throws {
    let cli = LeewayCLI(provider: FixtureProvider())
    let data = Data(try await cli.run(["status", "--json"]).utf8)
    #expect(try JSONCodec.decoder().decode(StatusDocument.self, from: data).accounts.first?.id == "first")
    let text = try await cli.run(["status"])
    #expect(text.contains("First"))
    #expect(text.contains("20%"))
}

@Test func cliHeadroomIsCeilingMinusUsedAndAdviceIsJSON() async throws {
    let cli = LeewayCLI(provider: FixtureProvider())
    let text = try await cli.run(["headroom", "--account", "First", "--json"])
    let raw = try #require(jsonObject(Data(text.utf8)))
    #expect(raw["headroom_pct"] as? Double == 55)
    let advice = try await cli.run(["advise", "--repo", "/example", "--role", "builder", "--task-class", "integration", "--agent", "claude"])
    #expect(try JSONCodec.decoder().decode(Advice.self, from: Data(advice.utf8)).verdict == .go)
}

@Test(arguments: [["unknown"], ["headroom"], ["advise", "--repo", "/x"], ["status", "--bogus"], ["headroom", "--account", "absent"]])
func cliInvalidInputFails(_ arguments: [String]) async {
    do {
        _ = try await LeewayCLI(provider: FixtureProvider()).run(arguments)
        Issue.record("invalid CLI input was accepted")
    } catch { #expect(error is CoreError) }
}

struct FixtureIntegrations: IntegrationCommand {
    func run(_ arguments: [String]) async throws -> String { "integration " + arguments.joined(separator: " ") }
}

@Test func cliDelegatesIntegrationCommandsWithoutQuotaLogic() async throws {
    let cli = LeewayCLI(provider: FixtureProvider(), integrations: FixtureIntegrations())
    #expect(try await cli.run(["integrations", "install"]) == "integration install")
}

@Test(arguments: [["status", "--bogus"], ["status", "--json", "--json"], ["headroom", "--account"]])
func cliErrorsNameTheOffendingOption(_ arguments: [String]) async {
    do {
        _ = try await LeewayCLI(provider: FixtureProvider()).run(arguments)
        Issue.record("invalid options were accepted")
    } catch {
        #expect(String(describing: error).contains(arguments.last!))
    }
}

@Test func cliHelpExplainsCommandsAndGlobalOptions() {
    #expect(LeewayCLI.help.contains("--home PATH  Use"))
    #expect(LeewayCLI.help.contains("--policy PATH  Read"))
    #expect(LeewayCLI.help.contains("127.0.0.1"))
    #expect(LeewayCLI.help.contains("Examples:"))
}

@Test func cliMissingUsageDoesNotProduceUnknownSentences() async throws {
    let cli = LeewayCLI(provider: MissingCLIProvider())
    #expect(try await cli.run(["status"]) == "First (stale): no reading yet")
    #expect(try await cli.run(["headroom", "--account", "First"]) == "First: no reading yet")
}

private struct MissingCLIProvider: UsageProvider {
    func status(refresh: Bool) async throws -> StatusDocument {
        let value = account("first", week: nil, next: nil)
        return StatusDocument(generatedAt: now, accounts: [value])
    }
    func advise(_ request: AdviceRequest) async throws -> Advice { ask([]) }
}
