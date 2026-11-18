import Foundation

public enum Advisor {
    private struct Block {
        let reason: String
        let until: Date?
        let isWeekly: Bool
    }

    /// Applies user policy to cached status, trying eligible accounts in policy order.
    public static func advise(_ request: AdviceRequest, document: StatusDocument, policy: Policy) -> Advice {
        let candidates = candidates(request, accounts: document.accounts, policy: policy)
            .map { account in request.target.map { account.retargeted(to: $0) } ?? account }
        guard let first = candidates.first else {
            return Advice(verdict: .deny, agent: request.agent?.rawValue ?? "", reason: "no account is allowed for this project")
        }
        var blocks: [Block] = []
        for account in candidates {
            let action = policy.accounts.first { $0.id == account.id }?.overTarget ?? .switch
            guard let block = block(account, history: document.history[account.id] ?? [], action: action, now: document.generatedAt) else {
                return answer(request, policy, account, verdict: blocks.isEmpty ? .go : .switch,
                    reason: joined(blocks, suffix: room(account, switching: !blocks.isEmpty)))
            }
            if block.isWeekly, action == .warn {
                return answer(request, policy, account, verdict: .go, reason: block.reason + "; warning only")
            }
            blocks.append(block)
            if block.isWeekly, action == .block {
                return answer(request, policy, account, verdict: .deny, reason: joined(blocks))
            }
        }
        let retry = blocks.compactMap(\.until).min()
        return answer(request, policy, first, verdict: retry == nil ? .deny : .wait,
            reason: joined(blocks), retry: retry)
    }

    private static func candidates(_ request: AdviceRequest, accounts: [AccountStatus], policy: Policy) -> [AccountStatus] {
        let agents: [Provider] = request.agent.map { [$0] }
            ?? ([Role.builder, .reviewer].contains(request.role) ? [.codex, .claude] : [.claude])
        let allowed = policy.allowed(for: request.repo)
        let ordered = agents.flatMap { provider -> [AccountStatus] in
            let mine = accounts.filter { $0.provider == provider }
            let names = provider == .codex ? allowed.codex : allowed.claude
            return names.map { names in names.flatMap { name in mine.filter { $0.id == name } } } ?? mine
        }
        guard let preferred = preferredAccount(request, ordered: ordered) else { return [] }
        if let names = request.candidates {
            let listed = names.flatMap { name in ordered.filter { $0.id == name || $0.label == name } }
            return distinct(preferred + listed)
        }
        guard let first = preferred.first else { return ordered }
        let reserve = policy.accounts.first { $0.id == first.id }?.reserveAccount
        return [first] + ordered.filter { $0.id == reserve && $0.id != first.id }
    }

    /// The account named by `request.account`: empty when none was named, nil when it is unknown or ambiguous.
    private static func preferredAccount(_ request: AdviceRequest, ordered: [AccountStatus]) -> [AccountStatus]? {
        guard let selected = request.account else { return [] }
        let matches = ordered.filter { $0.id == selected || $0.label == selected }
        return matches.count == 1 ? matches : nil
    }

    private static func distinct(_ accounts: [AccountStatus]) -> [AccountStatus] {
        var seen = Set<String>()
        return accounts.filter { seen.insert($0.id).inserted }
    }

    /// The account's block, with the earliest time it can be asked again. A five-hour block and an over-target
    /// week are independent, so when both hold the wait lasts until the later of the two clears.
    private static func block(_ account: AccountStatus, history: [HistoryPoint], action: TargetAction, now: Date) -> Block? {
        let weekly = account.status == .over
            ? Block(reason: weeklyReason(account), until: WeeklyRetry.clearsAt(account, history: history, now: now), isWeekly: true) : nil
        guard let five = account.fiveHour.pct, five >= 95 else { return weekly }
        let weeklyUntil = action == .warn ? nil : weekly?.until
        return Block(reason: "\(account.label) five-hour window is at \(Int(five.rounded()))%",
            until: account.fiveHour.resetsAt.map { max($0, weeklyUntil ?? $0) }, isWeekly: false)
    }

    private static func weeklyReason(_ account: AccountStatus) -> String {
        let reading = account.forecast.rangeHigh.map {
            "\(account.label) is forecast at \(percent($0)) of its week"
        } ?? "\(account.label) has \(percent(account.sevenDay.pct ?? 0)) of its week used"
        let limit = "over its \(percent(account.targetLow))-\(percent(account.targetHigh)) target"
        return reading + ", " + limit
    }

    private static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func room(_ account: AccountStatus, switching: Bool) -> String {
        let name = "\(account.label) (\(account.provider.rawValue))"
        let usage = account.sevenDay.pct.map { "\(Int($0.rounded()))% of its week used" } ?? "no reading, allowed"
        return switching ? "switching to \(name), \(usage)" : "\(name) has room: \(usage)"
    }

    private static func joined(_ blocks: [Block], suffix: String? = nil) -> String {
        (blocks.map(\.reason) + (suffix.map { [$0] } ?? [])).joined(separator: "; ")
    }

    private static func answer(_ request: AdviceRequest, _ policy: Policy, _ account: AccountStatus,
                               verdict: Verdict, reason: String, retry: Date? = nil) -> Advice {
        let choice = ModelRouter.choose(account.provider, role: request.role, task: request.taskClass, policy: policy)
        return Advice(verdict: verdict, agent: account.provider.rawValue, account: account.id, model: choice.model,
            effort: choice.effort, configDir: account.configDir, reason: reason, retryAt: retry,
            headroomPct: account.status == .under ? account.forecast.rangeHigh.map { account.targetLow - $0 } : nil,
            targetUsed: account.targetHigh)
    }
}

private extension AccountStatus {
    /// The same reading judged against a caller's landing target instead of the policy target high.
    /// The low edge never rises above the new high, so the interval stays valid.
    func retargeted(to target: Double) -> AccountStatus {
        AccountStatus(id: id, label: label, provider: provider, configDir: configDir, registered: registered,
            aliases: aliases, plan: plan, fiveHour: fiveHour, sevenDay: sevenDay, forecast: forecast, source: source,
            stale: stale, error: error, asOf: asOf, targetLow: min(targetLow, target), targetHigh: target)
    }
}
