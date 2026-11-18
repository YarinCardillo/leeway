import Foundation

// Versioned API encoders preserve unknown values as explicit JSON nulls.

public enum Verdict: String, Codable, Sendable { case go, `switch`, wait, deny }

public struct UsageWindow: Codable, Equatable, Sendable {
    public let pct: Double?
    public let resetsAt: Date?

    public init(pct: Double? = nil, resetsAt: Date? = nil) {
        self.pct = pct
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey { case pct, resetsAt }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(pct, forKey: .pct)
        try fields.encode(resetsAt, forKey: .resetsAt)
    }
}

public struct Snapshot: Codable, Equatable, Sendable {
    public let account: String
    public let at: Date
    public let plan: String?
    public let fiveHour: UsageWindow
    public let sevenDay: UsageWindow

    public init(account: String, at: Date, plan: String? = nil, fiveHour: UsageWindow = UsageWindow(), sevenDay: UsageWindow = UsageWindow()) {
        self.account = account
        self.at = at
        self.plan = plan
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    enum CodingKeys: String, CodingKey { case account, at, plan, fiveHour, sevenDay }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(account, forKey: .account)
        try fields.encode(at, forKey: .at)
        try fields.encode(plan, forKey: .plan)
        try fields.encode(fiveHour, forKey: .fiveHour)
        try fields.encode(sevenDay, forKey: .sevenDay)
    }
}

public struct Target: Codable, Equatable, Sendable {
    public let id: String
    public let provider: Provider
    public let label: String
    public let configDir: URL
    public let registered: Bool

    public init(id: String, provider: Provider, label: String, configDir: URL, registered: Bool = false) {
        self.id = id
        self.provider = provider
        self.label = label
        self.configDir = configDir
        self.registered = registered
    }
}

public struct AccountStatus: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let provider: Provider
    public let configDir: String
    public let registered: Bool
    public let aliases: [String]
    public let plan: String?
    public let fiveHour: UsageWindow
    public let sevenDay: UsageWindow
    public let forecast: Forecast
    public let source: String?
    public let stale: Bool
    public let error: AccountReadError?
    public let asOf: Date?
    public let targetLow: Double
    public let targetHigh: Double
    public let hoursEarly: Double?
    public let severity: RiskSeverity?
    public let status: AccountRisk

    public init(id: String, label: String, provider: Provider, configDir: String, registered: Bool = false, aliases: [String] = [], plan: String? = nil, fiveHour: UsageWindow = UsageWindow(), sevenDay: UsageWindow = UsageWindow(), forecast: Forecast = .empty, source: String? = nil, stale: Bool = true, error: AccountReadError? = nil, asOf: Date? = nil, targetLow: Double = 75, targetHigh: Double = 100, status: AccountRisk? = nil) {
        self.id = id
        self.label = label
        self.provider = provider
        self.configDir = configDir
        self.registered = registered
        self.aliases = aliases
        self.plan = plan
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.forecast = forecast
        self.source = source
        self.stale = stale
        self.error = error
        self.asOf = asOf
        self.targetLow = targetLow
        self.targetHigh = targetHigh
        let verdict = status ?? AccountRisk.evaluate(low: forecast.rangeLow, high: forecast.rangeHigh,
                                                     targetLow: targetLow, targetHigh: targetHigh)
        self.status = verdict
        self.hoursEarly = verdict.hoursEarly(exhaustsAt: forecast.exhaustsAt, reset: sevenDay.resetsAt)
        self.severity = verdict.severity(hoursEarly: hoursEarly)
    }

    enum CodingKeys: String, CodingKey { case id, label, provider, configDir, registered, aliases, plan, fiveHour, sevenDay, forecast, source, stale, error, asOf, targetLow, targetHigh, hoursEarly, severity, status }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(id, forKey: .id)
        try fields.encode(label, forKey: .label)
        try fields.encode(provider, forKey: .provider)
        try fields.encode(configDir, forKey: .configDir)
        try fields.encode(registered, forKey: .registered)
        try fields.encode(aliases, forKey: .aliases)
        try fields.encode(plan, forKey: .plan)
        try fields.encode(fiveHour, forKey: .fiveHour)
        try fields.encode(sevenDay, forKey: .sevenDay)
        try fields.encode(forecast, forKey: .forecast)
        try fields.encode(source, forKey: .source)
        try fields.encode(stale, forKey: .stale)
        try fields.encode(error, forKey: .error)
        try fields.encode(asOf, forKey: .asOf)
        try fields.encode(targetLow, forKey: .targetLow)
        try fields.encode(targetHigh, forKey: .targetHigh)
        try fields.encode(hoursEarly, forKey: .hoursEarly)
        try fields.encode(severity, forKey: .severity)
        try fields.encode(status, forKey: .status)
    }
}

/// Which process polls quota, from the point of view of the process that built the document.
public enum Poller: String, Codable, Equatable, Sendable {
    case thisProcess = "self"
    case otherProcess = "other"
    case nobody = "none"
}

public struct StatusDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let poller: Poller
    public let accounts: [AccountStatus]
    public let history: [String: [HistoryPoint]]

    /// The `schema_version` this build writes.
    public static let currentSchemaVersion = 4

    public init(schemaVersion: Int = StatusDocument.currentSchemaVersion, generatedAt: Date, poller: Poller = .thisProcess,
                accounts: [AccountStatus] = [], history: [String: [HistoryPoint]] = [:]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.poller = poller
        self.accounts = accounts
        self.history = history
    }

    enum CodingKeys: String, CodingKey { case schemaVersion, generatedAt, poller, accounts, history }

    /// Documents written before schema 4 carry no poller; they decode as `nobody`.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try fields.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try fields.decode(Date.self, forKey: .generatedAt)
        poller = try fields.decodeIfPresent(Poller.self, forKey: .poller) ?? .nobody
        accounts = try fields.decode([AccountStatus].self, forKey: .accounts)
        history = try fields.decode([String: [HistoryPoint]].self, forKey: .history)
    }
}

public struct AdviceRequest: Codable, Equatable, Sendable {
    public let repo: String
    public let role: Role
    public let taskClass: TaskClass
    public let agent: Provider?
    public let account: String?
    /// Landing target in percent of the week (1 to 100) that replaces the policy target for this answer.
    public let target: Double?
    /// Accounts to try, in order, instead of the preferred account's configured reserve.
    public let candidates: [String]?

    public init(repo: String, role: Role, taskClass: TaskClass, agent: Provider? = nil, account: String? = nil,
                target: Double? = nil, candidates: [String]? = nil) {
        self.repo = repo
        self.role = role
        self.taskClass = taskClass
        self.agent = agent
        self.account = account
        self.target = target
        self.candidates = candidates
    }

    enum CodingKeys: String, CodingKey { case repo, role, taskClass, agent, account, target, candidates }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(repo, forKey: .repo)
        try fields.encode(role, forKey: .role)
        try fields.encode(taskClass, forKey: .taskClass)
        try fields.encode(agent, forKey: .agent)
        try fields.encode(account, forKey: .account)
        try fields.encode(target, forKey: .target)
        try fields.encode(candidates, forKey: .candidates)
    }
}

public struct Advice: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let verdict: Verdict
    public let agent: String
    public let account: String
    public let model: String
    public let effort: String
    public let configDir: String
    public let reason: String
    public let retryAt: Date?
    public let headroomPct: Double?
    /// The weekly landing target, in percent, the answer was judged against.
    public let targetUsed: Double?

    /// The schema of advice answers.
    public static let currentSchemaVersion = 2

    public init(schemaVersion: Int = Advice.currentSchemaVersion, verdict: Verdict, agent: String = "", account: String = "", model: String = "", effort: String = "", configDir: String = "", reason: String, retryAt: Date? = nil, headroomPct: Double? = nil, targetUsed: Double? = nil) {
        self.schemaVersion = schemaVersion
        self.verdict = verdict
        self.agent = agent
        self.account = account
        self.model = model
        self.effort = effort
        self.configDir = configDir
        self.reason = reason
        self.retryAt = retryAt
        self.headroomPct = headroomPct
        self.targetUsed = targetUsed
    }

    enum CodingKeys: String, CodingKey { case schemaVersion, verdict, agent, account, model, effort, configDir, reason, retryAt, headroomPct, targetUsed }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(schemaVersion, forKey: .schemaVersion)
        try fields.encode(verdict, forKey: .verdict)
        try fields.encode(agent, forKey: .agent)
        try fields.encode(account, forKey: .account)
        try fields.encode(model, forKey: .model)
        try fields.encode(effort, forKey: .effort)
        try fields.encode(configDir, forKey: .configDir)
        try fields.encode(reason, forKey: .reason)
        try fields.encode(retryAt, forKey: .retryAt)
        try fields.encode(headroomPct, forKey: .headroomPct)
        try fields.encode(targetUsed, forKey: .targetUsed)
    }
}
