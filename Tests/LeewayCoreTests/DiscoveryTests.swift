import Foundation
import Testing
@testable import LeewayCore

@Test func discoveryIncludesDefaultsProfilesAndAddedHomesWithoutReadingCredentials() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let profile = home.appendingPathComponent("Library/Application Support/orca/claude-profiles/example-profile/home")
    for directory in [home.appendingPathComponent(".claude"), home.appendingPathComponent(".codex"), profile] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try Data("not valid JSON, discovery must never open this".utf8).write(to: profile.appendingPathComponent(".claude.json"))
    let found = try TargetDiscovery.discover(home: home, accounts: [], environment: [:])
    #expect(found.count == 3)
    #expect(found.filter { $0.provider == .claude }.count == 2)
    #expect(found.map(\.label).allSatisfy { !$0.contains("@") })
    #expect(found == (try TargetDiscovery.discover(home: home, accounts: [], environment: [:])))
}

@Test func discoveryDeduplicatesSymlinksAndSuppressesDisabledDefaults() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let directory = home.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let link = home.appendingPathComponent("alternate")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
    let account = AccountConfiguration(id: "first", provider: .claude, label: "First", configDir: link)
    let found = try TargetDiscovery.discover(home: home, accounts: [account], environment: ["CLAUDE_CONFIG_DIR": directory.path])
    #expect(found.count == 1)
    #expect(found.first?.id == "first")
    #expect(found.first?.registered == true)
    let disabled = AccountConfiguration(id: "first", provider: .claude, configDir: link, isEnabled: false)
    #expect(try TargetDiscovery.discover(home: home, accounts: [disabled], environment: [:]).isEmpty)
}

@Test func discoveryNamesUseFoldersInsteadOfCounters() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let profile = home.appendingPathComponent("Library/Application Support/orca/claude-profiles/opaque-id/home")
    let custom = home.appendingPathComponent(".claude-work")
    for directory in [home.appendingPathComponent(".claude"), home.appendingPathComponent(".codex"), profile, custom] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try Data().write(to: profile.appendingPathComponent(".claude.json"))
    let found = try TargetDiscovery.discover(home: home, accounts: [], environment: ["CLAUDE_CONFIG_DIR": custom.path])
    #expect(found.map(\.label) == ["Claude", "Codex", "Claude (Orca profile)", "Claude (claude-work)"])
}

@Test func discoveryPreservesExplicitNames() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let directory = home.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let registered = AccountConfiguration(id: "work", provider: .claude, label: "Research", configDir: directory)
    #expect(try TargetDiscovery.discover(home: home, accounts: [registered], environment: [:]).first?.label == "Research")
}

@Test func defaultLabelsNeverUseEmailFoldersAndKeepContextShort() {
    #expect(AccountLabel.defaultName(provider: .claude, directory: URL(fileURLWithPath: "/fixture/person@example.com")) == "Claude (custom folder)")
    #expect(AccountLabel.defaultName(provider: .codex, directory: URL(fileURLWithPath: "/fixture/work/.codex")) == "Codex (work)")
    #expect(AccountLabel.defaultName(provider: .claude, directory: URL(fileURLWithPath: "/fixture/" + String(repeating: "a", count: 100))).count <= 33)
}

@Test func configuredAccountWithoutANameUsesItsFolder() throws {
    let home = URL(fileURLWithPath: "/fixture")
    let policy = try Policy.parse("""
    [[accounts]]
    id = "work-id"
    provider = "claude"
    config_dir = "/fixture/.claude-work"
    """, home: home)
    #expect(policy.accounts.first?.label == "Claude (claude-work)")
}
