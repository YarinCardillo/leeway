import Foundation

/// How an account entered the book: found by structure, or added by the user.
public enum AccountOrigin: String, Codable, Sendable { case discovered, added }

/// A target found by discovery, with how it was found.
public struct DiscoveredAccount: Sendable, Equatable {
    public let target: Target
    public let origin: AccountOrigin

    public init(target: Target, origin: AccountOrigin) { self.target = target; self.origin = origin }
}

/// One row of the account book. The label is absent until the user renames the account.
public struct AccountEntry: Codable, Equatable, Sendable {
    public internal(set) var id: String
    public let provider: Provider
    public internal(set) var label: String?
    public let configDir: String
    public let origin: AccountOrigin
    public internal(set) var hidden: Bool
    public internal(set) var order: Int
}

/// The single list of accounts every Leeway client reads: which folders are accounts, what the user
/// renamed, hid, removed or ordered. Quota targets and rules stay in the policy file.
///
/// A removed folder stays out of discovery until it is added again. A hidden account stays in the book
/// but is neither shown nor polled until it is shown again.
public struct AccountBook: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    static let maximumLabelLength = 80

    public private(set) var schemaVersion = AccountBook.currentSchemaVersion
    public private(set) var accounts: [AccountEntry] = []
    public private(set) var removedFolders: [String] = []
    /// True once the Leeway app copied its older preferences into the book, so they are never read again.
    public private(set) var appPreferencesImported = false

    public init() {}

    /// Decodes a book, tolerating files written before `app_preferences_imported` existed.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try fields.decode(Int.self, forKey: .schemaVersion)
        accounts = try fields.decode([AccountEntry].self, forKey: .accounts)
        removedFolders = try fields.decode([String].self, forKey: .removedFolders)
        appPreferencesImported = try fields.decodeIfPresent(Bool.self, forKey: .appPreferencesImported) ?? false
    }

    /// Where the book of a home folder lives.
    public static func fileURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/leeway/accounts.json")
    }

    /// Reads a book. A missing file is an empty book; a newer or damaged file throws and is never replaced.
    public static func load(_ url: URL) throws -> AccountBook {
        guard FileManager.default.fileExists(atPath: url.path) else { return AccountBook() }
        guard let data = try? Data(contentsOf: url) else { throw CoreError.accountBookUnreadable }
        guard let book = try? JSONCodec.decoder().decode(AccountBook.self, from: data) else {
            throw CoreError.accountBookUnreadable
        }
        guard book.schemaVersion <= currentSchemaVersion else { throw CoreError.storeNewerThanBinary }
        return book
    }

    /// Writes the book atomically with private permissions.
    public func save(to url: URL) throws {
        try PrivateStorage.write(try JSONCodec.encoder().encode(self), to: url)
    }

    /// Entries in display order.
    public var ordered: [AccountEntry] { accounts.sorted { ($0.order, $0.id) < ($1.order, $1.id) } }

    /// Whether the folder was removed and must not be discovered again.
    public func isRemoved(_ folder: URL) -> Bool { removedFolders.contains(Self.normalized(folder.path)) }

    /// Whether discovery must skip this folder: it was removed, or its entry is hidden.
    public func excludes(_ provider: Provider, _ folder: URL) -> Bool {
        isRemoved(folder) || accounts.contains { $0.hidden && $0.provider == provider && Self.same($0.configDir, folder.path) }
    }

    /// The user's name for an account folder, if one was set.
    public func label(_ provider: Provider, _ folder: URL) -> String? {
        accounts.first { $0.provider == provider && Self.same($0.configDir, folder.path) }?.label
    }

    // MARK: Changes

    /// Adds entries for accounts the book has not seen and keeps each entry's id equal to the id clients see.
    public mutating func reconcile(with found: [DiscoveredAccount]) {
        for item in found {
            let target = item.target
            if let index = accounts.firstIndex(where: { $0.provider == target.provider && Self.same($0.configDir, target.configDir.path) }) {
                accounts[index].id = target.id
            } else {
                accounts.append(AccountEntry(id: target.id, provider: target.provider, label: nil,
                    configDir: target.configDir.path, origin: item.origin, hidden: false, order: nextOrder))
            }
        }
    }

    /// Gives an account a name of its own.
    public mutating func rename(id: String, label: String) throws {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= Self.maximumLabelLength else {
            throw CoreError.invalidRequest("the name must be 1 to \(Self.maximumLabelLength) characters")
        }
        try update(id) { $0.label = trimmed }
    }

    /// Hides an account from every client and stops polling it.
    public mutating func hide(id: String) throws { try update(id) { $0.hidden = true } }

    /// Shows a hidden account again.
    public mutating func show(id: String) throws { try update(id) { $0.hidden = false } }

    /// Removes an account and remembers its folder so discovery does not bring it back.
    public mutating func remove(id: String) throws {
        guard let entry = accounts.first(where: { $0.id == id }) else { throw CoreError.accountNotFound }
        remove(folder: entry.configDir)
    }

    /// Removes every account at a folder, known to the book or not, and remembers the folder.
    public mutating func remove(folder: String) {
        let normalized = Self.normalized(folder)
        accounts.removeAll { Self.normalized($0.configDir) == normalized }
        if !removedFolders.contains(normalized) { removedFolders.append(normalized) }
    }

    /// Adds a folder as an account, or brings back a removed or hidden one. The folder must exist.
    public mutating func add(folder: String, provider: Provider) throws {
        guard isDirectory(URL(fileURLWithPath: folder)) else { throw CoreError.invalidRequest("that folder does not exist") }
        restore(folder: folder, provider: provider)
    }

    /// Puts the listed accounts first, in this order. The others follow in their current order.
    public mutating func setOrder(_ ids: [String]) {
        let known = ids.filter { id in accounts.contains { $0.id == id } }
        let listed = known.compactMap { id in accounts.first { $0.id == id } }
        let rest = ordered.filter { !known.contains($0.id) }
        for (position, entry) in (listed + rest).enumerated() {
            if let index = accounts.firstIndex(where: { $0.id == entry.id }) { accounts[index].order = position }
        }
    }

    /// Copies the app's older preferences into the book once. Later calls change nothing.
    public mutating func importAppPreferences(addedFolders: [(path: String, provider: Provider)], order: [String]) {
        guard !appPreferencesImported else { return }
        for folder in addedFolders { restore(folder: folder.path, provider: folder.provider) }
        setOrder(order)
        appPreferencesImported = true
    }

    // MARK: Helpers

    static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func same(_ first: String, _ second: String) -> Bool { normalized(first) == normalized(second) }

    private var nextOrder: Int { (accounts.map(\.order).max() ?? -1) + 1 }

    private mutating func restore(folder: String, provider: Provider) {
        removedFolders.removeAll { $0 == Self.normalized(folder) }
        if let index = accounts.firstIndex(where: { $0.provider == provider && Self.same($0.configDir, folder) }) {
            accounts[index].hidden = false
            return
        }
        let url = URL(fileURLWithPath: folder)
        accounts.append(AccountEntry(id: uniqueID(provider.rawValue + "-" + TargetDiscovery.stableID(url)), provider: provider,
            label: nil, configDir: folder, origin: .added, hidden: false, order: nextOrder))
    }

    private func uniqueID(_ base: String) -> String {
        var result = base, suffix = 1
        while accounts.contains(where: { $0.id == result }) { suffix += 1; result = "\(base)-\(suffix)" }
        return result
    }

    private mutating func update(_ id: String, _ change: (inout AccountEntry) -> Void) throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw CoreError.accountNotFound }
        change(&accounts[index])
    }
}
