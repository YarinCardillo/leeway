import Foundation
import Testing
import CSQLite
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

@Test func cliVersionJson_NamesTheContractsAndTheStoreSchema() throws {
    let text = try LeewayCLI.runVersion(["--json"])
    let raw = try #require(jsonObject(Data(text.utf8)))
    #expect(Set(raw.keys) == ["schema_version", "version", "status_schema", "accounts_schema", "advice_schema", "store_schema"])
    #expect(raw["schema_version"] as? Int == 1)
    #expect(raw["version"] as? String == LeewayVersion.current)
    #expect(raw["status_schema"] as? Int == StatusDocument.currentSchemaVersion)
    #expect(raw["status_schema"] as? Int == 4)
    #expect(raw["accounts_schema"] as? Int == 1)
    #expect(raw["advice_schema"] as? Int == 2)
    #expect(raw["store_schema"] as? Int == SnapshotStore.schemaVersion)
    #expect(try LeewayCLI.runVersion([]) == "leeway " + LeewayVersion.current)
}

@Test func cliVersionRejectsOtherOptions() {
    #expect(throws: CoreError.self) { try LeewayCLI.runVersion(["--bogus"]) }
}

@Test func leewayVersion_MatchesTheReleaseInput() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let xcconfig = try String(contentsOf: root.appendingPathComponent("App/Version.xcconfig"), encoding: .utf8)
    let line = try #require(xcconfig.split(separator: "\n").first { $0.hasPrefix("LEEWAY_RELEASE_VERSION = ") })
    #expect(line.dropFirst("LEEWAY_RELEASE_VERSION = ".count) == LeewayVersion.current)
}

private let olderBinaryMessage = "this leeway is older than the data it would read; use the newer one"

/// Runs the built `leeway` executable against a throwaway home whose store claims a newer schema.
private func runBuiltLeeway(_ arguments: [String]) throws -> (output: ProcessOutput, home: URL, history: URL, before: Data) {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let executable = root.appendingPathComponent(".build/debug/leeway")
    try #require(FileManager.default.isExecutableFile(atPath: executable.path), "build the leeway product before testing it")
    let home = try temporaryDirectory()
    let history = home.appendingPathComponent("Library/Application Support/leeway/history.sqlite")
    _ = try SnapshotStore(path: history.path)
    try stampStoreSchema(history.path, SnapshotStore.schemaVersion + 1)
    let before = try Data(contentsOf: history)
    let request = ProcessRequest(executable: executable.path, arguments: ["--home", home.path] + arguments,
        environment: ["PATH": "/usr/bin:/bin"], workingDirectory: home, timeout: 20)
    return (try SystemProcessRunner().run(request), home, history, before)
}

private func stampStoreSchema(_ path: String, _ version: Int) throws {
    var connection: OpaquePointer?
    try #require(sqlite3_open(path, &connection) == SQLITE_OK)
    defer { sqlite3_close(connection) }
    try #require(sqlite3_exec(connection, "PRAGMA user_version = \(version)", nil, nil, nil) == SQLITE_OK)
}

/// One test, not one per verb: each run blocks a thread, and parallel runs starve unrelated timing tests.
@Test func cliOlderThanTheStore_EveryVerbExitsThreeAndLeavesTheFileUntouched() throws {
    let verbs = [["status", "--json"], ["refresh", "--json"], ["headroom", "--account", "x"],
                 ["advise", "--repo", "/x", "--role", "builder", "--task-class", "integration"], ["serve"]]
    for arguments in verbs {
        let result = try runBuiltLeeway(arguments)
        defer { try? FileManager.default.removeItem(at: result.home) }
        #expect(result.output.exitCode == 3, "\(arguments)")
        let raw = try #require(jsonObject(Data(result.output.stdout.utf8)))
        #expect(raw["schema_version"] as? Int == 1, "\(arguments)")
        #expect(raw["error"] as? String == olderBinaryMessage, "\(arguments)")
        #expect(try Data(contentsOf: result.history) == result.before, "\(arguments)")
    }
}

@Test func cliVersion_AgainstANewerStore_StillAnswersSoACallerCanPickTheNewerBinary() throws {
    let result = try runBuiltLeeway(["version", "--json"])
    defer { try? FileManager.default.removeItem(at: result.home) }
    #expect(result.output.exitCode == 0)
    let raw = try #require(jsonObject(Data(result.output.stdout.utf8)))
    #expect(raw["store_schema"] as? Int == SnapshotStore.schemaVersion)
    #expect(try Data(contentsOf: result.history) == result.before)
}
