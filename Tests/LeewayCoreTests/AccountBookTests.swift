import Foundation
import Testing
@testable import LeewayCore

private func makeHome() throws -> URL {
    let home = try temporaryDirectory()
    for name in [".claude", ".codex"] {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    return home
}

private func command(_ home: URL) -> AccountsCommand {
    AccountsCommand(home: home, policy: Policy(), environment: [:])
}

private func rows(_ text: String) throws -> [[String: Any]] {
    let raw = try #require(jsonObject(Data(text.utf8)))
    #expect(raw["schema_version"] as? Int == 1)
    return try #require(raw["accounts"] as? [[String: Any]])
}

private func isStoreNewer(_ error: any Error) -> Bool {
    if case .storeNewerThanBinary? = error as? CoreError { return true }
    return false
}

private func discovered(_ home: URL) throws -> [Target] {
    let book = try AccountBook.load(AccountBook.fileURL(home: home))
    return try TargetDiscovery.discover(home: home, accounts: [], environment: [:], book: book)
}

@Test func accountsListShowsEveryAccountWithoutEmailsOrCredentialContents() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try Data(#"{"email":"someone@example.com","token":"secret-token"}"#.utf8)
        .write(to: home.appendingPathComponent(".claude/.credentials.json"))
    let text = try command(home).run(["list", "--json"])
    #expect(!text.contains("example.com") && !text.contains("secret-token") && !text.contains(home.path))
    let list = try rows(text)
    #expect(list.map { $0["id"] as? String } == ["claude-default", "codex-default"])
    #expect(list.map { $0["order"] as? Int } == [0, 1])
    #expect(list.allSatisfy { $0["origin"] as? String == "discovered" && $0["hidden"] as? Bool == false && $0["folder_exists"] as? Bool == true })
    #expect(Set(list[0].keys) == ["id", "provider", "label", "origin", "hidden", "folder_exists", "order"])
}

@Test func removedDiscoveredAccountStaysRemovedAfterRediscovery() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let removed = try rows(command(home).run(["remove", "claude-default", "--json"]))
    #expect(removed.map { $0["id"] as? String } == ["codex-default"])
    #expect(try discovered(home).map(\.id) == ["codex-default"])
    #expect(try rows(command(home).run(["list", "--json"])).map { $0["id"] as? String } == ["codex-default"])
}

@Test func addingTheFolderAgainBringsARemovedAccountBack() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try command(home).run(["remove", "claude-default"])
    let list = try rows(command(home).run(["add", home.appendingPathComponent(".claude").path, "--json"]))
    #expect(list.contains { $0["provider"] as? String == "claude" && $0["hidden"] as? Bool == false })
    #expect(try discovered(home).contains { $0.provider == .claude })
}

@Test func accountWhoseFolderIsGoneIsListedAsMissingAndCanBeRemoved() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try command(home).run(["rename", "codex-default", "Spare"])
    try FileManager.default.removeItem(at: home.appendingPathComponent(".codex"))
    let list = try rows(command(home).run(["list", "--json"]))
    let gone = try #require(list.first { $0["id"] as? String == "codex-default" })
    #expect(gone["folder_exists"] as? Bool == false)
    #expect(gone["label"] as? String == "Spare")
    let after = try rows(command(home).run(["remove", "codex-default", "--json"]))
    #expect(after.map { $0["id"] as? String } == ["claude-default"])
}

@Test func hiddenAccountIsNotDiscoveredUntilShownAgain() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let hidden = try rows(command(home).run(["hide", "claude-default", "--json"]))
    #expect(hidden.first { $0["id"] as? String == "claude-default" }?["hidden"] as? Bool == true)
    #expect(try discovered(home).map(\.id) == ["codex-default"])
    _ = try command(home).run(["show", "claude-default"])
    #expect(try discovered(home).map(\.id) == ["claude-default", "codex-default"])
}

@Test func renameChangesTheLabelEveryClientSees() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let list = try rows(command(home).run(["rename", "claude-default", "Work", "--json"]))
    #expect(list.first?["label"] as? String == "Work")
    #expect(try discovered(home).first?.label == "Work")
}

@Test func accountsCommandRejectsUnknownIdsMissingFoldersAndBadVerbs() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    for arguments in [["remove", "absent"], ["hide", "absent"], ["add", home.appendingPathComponent("nope").path],
                      ["rename", "claude-default", " "], ["bogus"], [], ["list", "--bogus"], ["add", home.path, "--provider", "other"]] {
        #expect(throws: CoreError.self) { try command(home).run(arguments) }
    }
}

@Test func bookFileIsPrivateAtomicAndRefusesNewerSchemas() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try command(home).run(["hide", "claude-default"])
    let url = AccountBook.fileURL(home: home)
    let mode = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    #expect(mode & 0o077 == 0)
    let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
    #expect(!siblings.contains { $0.hasPrefix(".leeway-") })
    var raw = try #require(jsonObject(Data(contentsOf: url)))
    #expect(raw["schema_version"] as? Int == 2)
    raw["schema_version"] = 3
    try JSONSerialization.data(withJSONObject: raw).write(to: url)
    #expect { try AccountBook.load(url) } throws: { isStoreNewer($0) }
    #expect { try command(home).run(["list"]) } throws: { isStoreNewer($0) }
    let before = try Data(contentsOf: url)
    #expect(throws: CoreError.self) { try command(home).run(["hide", "codex-default"]) }
    #expect(try Data(contentsOf: url) == before)
}

@Test func unreadableBookFileFailsInsteadOfBeingReplaced() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let url = AccountBook.fileURL(home: home)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    #expect(throws: CoreError.self) { try command(home).run(["hide", "claude-default"]) }
    #expect(try Data(contentsOf: url) == Data("not json".utf8))
}

@Test func concurrentEditsDoNotLoseEachOther() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let folders = try (0..<8).map { index -> URL in
        let folder = home.appendingPathComponent("extra-\(index)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    DispatchQueue.concurrentPerform(iterations: folders.count) { index in
        _ = try? command(home).run(["add", folders[index].path])
    }
    let list = try rows(command(home).run(["list", "--json"]))
    #expect(list.count == 10)
}

@Test func discoveryAppliesRemovedFoldersToPolicyAccountsToo() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let account = AccountConfiguration(id: "added-one", provider: .claude, label: "Added", configDir: home.appendingPathComponent(".claude"))
    var book = AccountBook()
    #expect(try TargetDiscovery.discover(home: home, accounts: [account], environment: [:], book: book).first?.id == "added-one")
    book.reconcile(with: try TargetDiscovery.discoverAccounts(home: home, accounts: [account], environment: [:], book: book))
    try book.remove(id: "added-one")
    #expect(try TargetDiscovery.discover(home: home, accounts: [account], environment: [:], book: book).map(\.id) == ["codex-default"])
}

@Test func orderIsKeptInTheBookAndPlacesUnlistedAccountsLast() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try AccountBookFile(url: AccountBook.fileURL(home: home)).update { book in
        book.reconcile(with: try TargetDiscovery.discoverAccounts(home: home, accounts: [], environment: [:], book: book))
        book.setOrder(["codex-default"])
    }
    let list = try rows(command(home).run(["list", "--json"]))
    #expect(list.map { $0["id"] as? String } == ["codex-default", "claude-default"])
}

@Test func serviceStatusOmitsRemovedAndHiddenAccountsAndNeverReadsThem() async throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try command(home).run(["remove", "claude-default"])
    let runner = FakeRunner(output: ProcessOutput(exitCode: 0, stdout: rateEvent(week: 0.5)))
    let service = UsageService(home: home, policy: Policy(), store: try SnapshotStore(path: ":memory:"),
        runner: runner, environment: [:], clock: { now })
    #expect(try await service.status(refresh: true).accounts.map(\.id) == ["codex-default"])
    #expect(runner.calls.isEmpty)
    _ = try command(home).run(["hide", "codex-default"])
    #expect(try await service.status(refresh: true).accounts.isEmpty)
}

@Test func cliRoutesAccountsVerbsAndTextListNamesProblems() async throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let cli = LeewayCLI(provider: FixtureProvider(), accounts: command(home))
    #expect(try rows(await cli.run(["accounts", "hide", "claude-default", "--json"])).count == 2)
    try FileManager.default.removeItem(at: home.appendingPathComponent(".codex"))
    let text = try await cli.run(["accounts", "list"])
    #expect(text.contains("Claude (claude-default): claude, discovered, hidden"))
    #expect(text.contains("Codex (codex-default): codex, discovered, folder not found"))
    await #expect(throws: CoreError.self) { try await LeewayCLI(provider: FixtureProvider()).run(["accounts", "list"]) }
}

@Test func importingAppPreferencesHappensOnceAndKeepsOrder() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let extra = home.appendingPathComponent("extra")
    try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
    var book = AccountBook()
    book.reconcile(with: try TargetDiscovery.discoverAccounts(home: home, accounts: [], environment: [:], book: book))
    book.importAppPreferences(addedFolders: [(extra.path, .codex)], order: ["codex-default", "claude-default"])
    #expect(book.appPreferencesImported)
    #expect(book.ordered.map(\.id).prefix(2) == ["codex-default", "claude-default"])
    #expect(book.accounts.last?.origin == .added && book.accounts.last?.provider == .codex)
    let snapshot = book
    book.importAppPreferences(addedFolders: [(home.path, .claude)], order: ["claude-default"])
    #expect(book == snapshot)
}

@Test func pollingRecordsDiscoveredAccountsSoAVanishedFolderStaysListed() async throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let service = UsageService(home: home, policy: Policy(), store: try SnapshotStore(path: ":memory:"),
        runner: FakeRunner(output: ProcessOutput(exitCode: 0, stdout: rateEvent(week: 0.5))), environment: [:], clock: { now })
    _ = try await service.status(refresh: true)
    try FileManager.default.removeItem(at: home.appendingPathComponent(".codex"))
    let list = try rows(command(home).run(["list", "--json"]))
    #expect(list.first { $0["id"] as? String == "codex-default" }?["folder_exists"] as? Bool == false)
    #expect(try await service.status().accounts.map(\.id) == ["claude-default"])
}

@Test func bookFileWrittenAsVersion1IsReadAndRewrittenAsVersion2() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let url = AccountBook.fileURL(home: home)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let claude = home.appendingPathComponent(".claude").path
    try Data(#"{"schema_version":1,"accounts":[{"id":"claude-default","provider":"claude","label":"Work","config_dir":"\#(claude)","origin":"discovered","hidden":false,"order":0}],"removed_folders":[]}"#.utf8).write(to: url)
    #expect(try AccountBook.load(url).accounts.map(\.label) == ["Work"])
    _ = try command(home).run(["hide", "claude-default"])
    let raw = try #require(jsonObject(Data(contentsOf: url)))
    #expect(raw["schema_version"] as? Int == 2)
    #expect(try AccountBook.load(url).accounts.first { $0.id == "claude-default" }?.label == "Work")
}
