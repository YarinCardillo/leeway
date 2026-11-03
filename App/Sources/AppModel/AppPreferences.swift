import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system, english, italian

    public var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .italian: Locale(identifier: "it")
        }
    }
}

public struct AccountPreference: Codable, Sendable, Equatable {
    public var name: String?
    public var isEnabled = true
    public var targetLow: Double = 75
    public var targetHigh: Double = 100
    public var reserveID: String?
    public var aliases: [String] = []

    public init(name: String? = nil, isEnabled: Bool = true, targetLow: Double = 75, targetHigh: Double = 100, reserveID: String? = nil) {
        self.name = name
        self.isEnabled = isEnabled
        self.targetLow = targetLow
        self.targetHigh = targetHigh
        self.reserveID = reserveID
    }
    private enum CodingKeys: String, CodingKey { case name, isEnabled, targetLow, targetHigh, reserveID, aliases }

    /// Decodes target settings, using defaults when no bounds were saved.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        reserveID = try values.decodeIfPresent(String.self, forKey: .reserveID)
        aliases = try values.decodeIfPresent([String].self, forKey: .aliases) ?? []
        targetLow = try values.decodeIfPresent(Double.self, forKey: .targetLow) ?? 75
        targetHigh = try values.decodeIfPresent(Double.self, forKey: .targetHigh) ?? 100
        guard (0...100).contains(targetLow), (0...100).contains(targetHigh), targetLow < targetHigh else {
            throw DecodingError.dataCorruptedError(forKey: .targetLow, in: values, debugDescription: "Invalid target range")
        }
    }

}

/// User-owned presentation and polling choices, persisted independently of readings.
public struct AppPreferences: Codable, Sendable {
    public var accounts: [String: AccountPreference] = [:]
    public var pinnedID: String?
    public var pollingMinutes = 15
    public var language = AppLanguage.system
    public var updatesAutomatically = true
    public var isMenuBarCompact = true
    public var accountOrderMode = AccountOrderMode.mostAtRisk
    public var manualAccountOrder: [String] = []
    public var addedFolders: [String] = []
    public var folderProviders: [String: String] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case accounts, pinnedID, pollingMinutes, language, updatesAutomatically
        case addedFolders, folderProviders, isMenuBarCompact, accountOrderMode, manualAccountOrder
    }

    /// New installs and preferences saved before compact mode both use the compact glyph.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try values.decode([String: AccountPreference].self, forKey: .accounts)
        pinnedID = try values.decodeIfPresent(String.self, forKey: .pinnedID)
        pollingMinutes = try values.decode(Int.self, forKey: .pollingMinutes)
        language = try values.decode(AppLanguage.self, forKey: .language)
        updatesAutomatically = try values.decode(Bool.self, forKey: .updatesAutomatically)
        addedFolders = try values.decode([String].self, forKey: .addedFolders)
        folderProviders = try values.decode([String: String].self, forKey: .folderProviders)
        isMenuBarCompact = try values.decodeIfPresent(Bool.self, forKey: .isMenuBarCompact) ?? true
        accountOrderMode = try values.decodeIfPresent(AccountOrderMode.self, forKey: .accountOrderMode) ?? .mostAtRisk
        manualAccountOrder = try values.decodeIfPresent([String].self, forKey: .manualAccountOrder) ?? []
    }

    public static let pollingChoices = [5, 10, 15, 30]
    public static let targetStep = 5.0
}
