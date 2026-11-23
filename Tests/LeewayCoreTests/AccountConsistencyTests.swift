import Foundation
import Testing
@testable import LeewayCore

private func makeHome() throws -> URL {
    let home = try temporaryDirectory()
    for name in [".claude", ".codex", "extra", "custom"] {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    return home
}

private func labels(_ text: String) throws -> [String: String] {
    let raw = try #require(jsonObject(Data(text.utf8)))
    let accounts = try #require(raw["accounts"] as? [[String: Any]])
    return Dictionary(uniqueKeysWithValues: accounts.compactMap { row in
        (row["id"] as? String).flatMap { id in (row["label"] as? String).map { (id, $0) } }
    })
}

@Test func importingAppPreferences_KeepsRemovedAndHiddenDecisions() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    var book = AccountBook()
    book.reconcile(with: try TargetDiscovery.discoverAccounts(home: home, accounts: [], environment: [:], book: book))
    let extra = home.appendingPathComponent("extra").path
    try book.add(folder: extra, provider: .codex)
    book.remove(folder: extra)
    try book.hide(id: "claude-default")
    book.importAppPreferences(addedFolders: [(extra, .codex), (home.appendingPathComponent(".claude").path, .claude)], order: [])
    #expect(book.isRemoved(URL(fileURLWithPath: extra)))
    #expect(!book.accounts.contains { $0.configDir == extra })
    #expect(book.accounts.first { $0.id == "claude-default" }?.hidden == true)
    #expect(book.appPreferencesImported)
}

@Test func importingAppPreferences_StillAddsFoldersTheBookHasNoDecisionAbout() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    var book = AccountBook()
    let extra = home.appendingPathComponent("extra").path
    book.importAppPreferences(addedFolders: [(extra, .codex)], order: [])
    #expect(book.accounts.map(\.configDir) == [extra])
    #expect(book.accounts.first?.origin == .added)
}

@Test func discovery_ReusesEverySavedAccountWhateverTheProcessEnvironment() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let custom = home.appendingPathComponent("custom")
    var book = AccountBook()
    book.reconcile(with: try TargetDiscovery.discoverAccounts(home: home, accounts: [],
        environment: ["CLAUDE_CONFIG_DIR": custom.path], book: book))
    let found = try TargetDiscovery.discoverAccounts(home: home, accounts: [], environment: [:], book: book)
    let saved = try #require(found.first { $0.target.configDir.path == custom.path })
    #expect(saved.origin == .discovered)
    #expect(saved.target.id == book.accounts.first { $0.configDir == custom.path }?.id)
}

@Test func discovery_SavedAccountsKeepTheirPlaceAfterTheAutomaticOnes() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    var book = AccountBook()
    book.reconcile(with: try TargetDiscovery.discoverAccounts(home: home, accounts: [],
        environment: ["CLAUDE_CONFIG_DIR": home.appendingPathComponent("custom").path], book: book))
    let ids = try TargetDiscovery.discover(home: home, accounts: [], environment: [:], book: book).map(\.id)
    #expect(Array(ids.prefix(2)) == ["claude-default", "codex-default"])
    #expect(ids.count == 3)
}

@Test func accountsList_ShowsAPolicyLabelAndRenameWinsOverItEverywhere() async throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let account = AccountConfiguration(id: "work", provider: .claude, label: "Work", configDir: home.appendingPathComponent("extra"))
    let policy = Policy(accounts: [account])
    let command = AccountsCommand(home: home, policy: policy, environment: [:])
    #expect(try labels(command.run(["list", "--json"]))["work"] == "Work")
    #expect(try labels(command.run(["rename", "work", "Office", "--json"]))["work"] == "Office")
    let book = try AccountBook.load(AccountBook.fileURL(home: home))
    let target = try #require(try TargetDiscovery.discover(home: home, accounts: [account], environment: [:], book: book)
        .first { $0.id == "work" })
    #expect(target.label == "Office")
    #expect(try labels(command.run(["list", "--json"]))["work"] == "Office")
}

@Test func accountsList_NeverTreatsADefaultPolicyLabelAsAName() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let account = AccountConfiguration(id: "plain", provider: .claude, label: AccountLabel.defaultName(provider: .claude,
        directory: home.appendingPathComponent("extra"), home: home), configDir: home.appendingPathComponent("extra"))
    let command = AccountsCommand(home: home, policy: Policy(accounts: [account]), environment: [:])
    let entry = try #require(try command.current().accounts.first { $0.id == "plain" })
    #expect(entry.label == nil)
    #expect(try labels(command.run(["list", "--json"]))["plain"] == account.label)
}

@Test func accountsList_ListsAPolicyAccountWhoseFolderIsMissingAndLetsItBeRemoved() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let gone = AccountConfiguration(id: "gone", provider: .claude, label: "Gone", configDir: home.appendingPathComponent("not-there"))
    let off = AccountConfiguration(id: "off", provider: .codex, label: "Off", configDir: home.appendingPathComponent("extra"), isEnabled: false)
    let command = AccountsCommand(home: home, policy: Policy(accounts: [gone, off]), environment: [:])
    let before = try labels(command.run(["list", "--json"]))
    #expect(before["gone"] == "Gone")
    #expect(before["off"] == "Off")
    #expect(try TargetDiscovery.discover(home: home, accounts: [gone, off], environment: [:],
        book: command.current()).allSatisfy { $0.id != "gone" && $0.id != "off" })
    for id in ["gone", "off"] { _ = try command.run(["remove", id]) }
    let after = try labels(command.run(["list", "--json"]))
    #expect(after["gone"] == nil)
    #expect(after["off"] == nil)
}

@Test func accountBook_DoesNotKeepTwoAccountsWithOneIDWhenAPolicyAccountChangesFolder() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let first = AccountConfiguration(id: "work", provider: .claude, label: "Work", configDir: home.appendingPathComponent("extra"))
    _ = try AccountsCommand(home: home, policy: Policy(accounts: [first]), environment: [:]).edit { _ in }
    let moved = AccountConfiguration(id: "work", provider: .claude, label: "Work", configDir: home.appendingPathComponent("custom"))
    let book = try AccountsCommand(home: home, policy: Policy(accounts: [moved]), environment: [:]).current()
    #expect(Set(book.accounts.map(\.id)).count == book.accounts.count)
    #expect(book.accounts.first { $0.id == "work" }?.configDir == moved.configDir.path)
    let targets = try TargetDiscovery.discover(home: home, accounts: [moved], environment: [:], book: book)
    #expect(Set(targets.map(\.id)).count == targets.count)
}

@Test func accountBook_LoadingABookWithTwoEntriesOfOneIDFailsAsUnreadable() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let url = AccountBook.fileURL(home: home)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let entry = { (folder: String) in
        "{\"id\":\"work\",\"provider\":\"claude\",\"config_dir\":\"\(folder)\",\"origin\":\"added\",\"hidden\":false,\"order\":0}"
    }
    let text = "{\"schema_version\":1,\"accounts\":[\(entry("/a")),\(entry("/b"))],\"removed_folders\":[]}"
    try Data(text.utf8).write(to: url)
    #expect { try AccountBook.load(url) } throws: { ($0 as? CoreError).map { $0.description == CoreError.accountBookUnreadable.description } ?? false }
}

@Test func accountBook_ANewerLayoutIsReportedAsNewerNotAsDamaged() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let url = AccountBook.fileURL(home: home)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let text = "{\"schema_version\":\(AccountBook.currentSchemaVersion + 1),\"accounts\":[{\"id\":\"x\",\"provider\":\"gemini\",\"folder\":\"/a\"}]}"
    try Data(text.utf8).write(to: url)
    #expect { try AccountBook.load(url) } throws: { ($0 as? CoreError).map { $0.description == CoreError.storeNewerThanBinary.description } ?? false }
}
