import Foundation

/// One account as `leeway accounts` prints it. It carries no folder path and nothing read from the folder.
public struct AccountRow: Codable, Equatable, Sendable {
    public let id: String
    public let provider: Provider
    public let label: String
    public let origin: AccountOrigin
    public let hidden: Bool
    public let folderExists: Bool
    public let order: Int
}

/// The versioned document of `leeway accounts ... --json`.
public struct AccountList: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let accounts: [AccountRow]
}

/// The `accounts` verbs: list, rename, hide, show, remove and add. They work on the account book and never
/// read quota or credentials, so they are safe to run beside a polling process.
public struct AccountsCommand: Sendable {
    private let home: URL
    private let policy: Policy
    private let environment: [String: String]

    public init(home: URL, policy: Policy, environment: [String: String]) {
        self.home = home; self.policy = policy; self.environment = environment
    }

    /// Runs one verb and returns the updated list, as JSON with `--json` and as text otherwise.
    public func run(_ arguments: [String]) throws -> String {
        guard let verb = arguments.first else { throw Self.usage }
        let input = try Input(Array(arguments.dropFirst()), allowsProvider: verb == "add")
        let book: AccountBook
        switch verb {
        case "list": try input.expect(0); book = try reconciled(file.load())
        case "rename": try input.expect(2); book = try edit { try $0.rename(id: input.positional[0], label: input.positional[1]) }
        case "hide": try input.expect(1); book = try edit { try $0.hide(id: input.positional[0]) }
        case "show": try input.expect(1); book = try edit { try $0.show(id: input.positional[0]) }
        case "remove": try input.expect(1); book = try edit { try $0.remove(id: input.positional[0]) }
        case "add": try input.expect(1); book = try edit { try $0.add(folder: input.positional[0], provider: input.provider) }
        default: throw Self.usage
        }
        let list = rows(book)
        return input.isJSON ? try JSONCodec.string(list) : Self.text(list)
    }

    /// Reconciles discovery into the saved book, runs one change, and saves the result under the book's lock.
    /// The Leeway app uses this for its own account changes.
    @discardableResult
    public func edit(_ change: (inout AccountBook) throws -> Void) throws -> AccountBook {
        try file.update { book in
            book = try reconciled(book)
            try change(&book)
            book = try reconciled(book)
            return book
        }
    }

    /// The saved book with every account discovery finds now, without writing anything.
    public func current() throws -> AccountBook { try reconciled(file.load()) }

    private static let usage = CoreError.invalidRequest(
        "usage: accounts list|rename ID NAME|hide ID|show ID|remove ID|add FOLDER [--provider claude|codex] [--json]")

    private var file: AccountBookFile { AccountBookFile(url: AccountBook.fileURL(home: home)) }

    private func reconciled(_ book: AccountBook) throws -> AccountBook {
        var result = book
        result.reconcile(with: try TargetDiscovery.catalogue(home: home, accounts: policy.accounts,
            environment: environment, book: result))
        result.adoptLabels(of: policy.accounts, home: home)
        return result
    }

    private func rows(_ book: AccountBook) -> AccountList {
        AccountList(schemaVersion: AccountList.currentSchemaVersion, accounts: book.ordered.map { entry in
            let folder = URL(fileURLWithPath: entry.configDir)
            return AccountRow(id: entry.id, provider: entry.provider,
                label: entry.label ?? AccountLabel.defaultName(provider: entry.provider, directory: folder, home: home),
                origin: entry.origin, hidden: entry.hidden, folderExists: isDirectory(folder), order: entry.order)
        })
    }

    private static func text(_ list: AccountList) -> String {
        guard !list.accounts.isEmpty else { return "No accounts found." }
        return list.accounts.map { row in
            var parts = [row.provider.rawValue, row.origin.rawValue]
            if row.hidden { parts.append("hidden") }
            if !row.folderExists { parts.append("folder not found") }
            return "\(row.label) (\(row.id)): " + parts.joined(separator: ", ")
        }.joined(separator: "\n")
    }
}

/// The words after the verb: positional values, `--json`, and `--provider` for `add`.
private struct Input {
    private(set) var positional: [String] = []
    private(set) var isJSON = false
    private(set) var provider = Provider.claude

    init(_ arguments: [String], allowsProvider: Bool) throws {
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            index += 1
            if word == "--json" { isJSON = true; continue }
            guard word == "--provider", allowsProvider else {
                if word.hasPrefix("--") { throw CoreError.invalidRequest("unknown option: \(word)") }
                positional.append(word)
                continue
            }
            guard index < arguments.count, let value = Provider(rawValue: arguments[index]) else {
                throw CoreError.invalidRequest("--provider must be claude or codex")
            }
            provider = value
            index += 1
        }
    }

    func expect(_ count: Int) throws {
        guard positional.count == count else { throw CoreError.invalidRequest("wrong number of values for this command") }
    }
}
