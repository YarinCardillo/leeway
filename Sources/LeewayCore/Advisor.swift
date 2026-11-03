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
        guard let first = candidates.first else {
            return Advice(verdict: .deny, agent: request.agent?.rawValue ?? "", reason: "no account is allowed for this project")
        }
        var blocks: [Block] = []
        for account in candidates {
            let action = policy.accounts.first { $0.id == account.id }?.overTarget ?? .switch
            guard let block = block(account) else {
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
        guard let selected = request.account else { return ordered }
        let matches = ordered.filter { $0.id == selected || $0.label == selected }
        guard matches.count == 1, let preferred = matches.first else { return [] }
        let reserve = policy.accounts.first { $0.id == preferred.id }?.reserveAccount
        return [preferred] + ordered.filter { $0.id == reserve && $0.id != preferred.id }
    }

    private static func block(_ account: AccountStatus) -> Block? {
        if let five = account.fiveHour.pct, five >= 95 {
            return Block(reason: "\(account.label) five-hour window is at \(Int(five.rounded()))%",
                until: account.fiveHour.resetsAt, isWeekly: false)
        }
        if account.status == .over {
            return Block(reason: weeklyReason(account), until: account.sevenDay.resetsAt, isWeekly: true)
        }
        return nil
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
            headroomPct: account.status == .under ? account.forecast.rangeHigh.map { account.targetLow - $0 } : nil)
    }
}
