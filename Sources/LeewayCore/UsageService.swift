import Foundation

public protocol UsageProvider: Sendable {
    func status(refresh: Bool) async throws -> StatusDocument
    func advise(_ request: AdviceRequest) async throws -> Advice
    /// Takes a reading now when another process asked for one through the shared store. Does nothing otherwise.
    /// Returns whether it served a request, so a client knows the store may hold new readings.
    @discardableResult
    func servePendingRefresh() async -> Bool
    /// One scheduled round. Unlike `status(refresh: true)`, it never asks another process for a reading:
    /// a process that cannot poll leaves the store as it is.
    func pollRound() async throws
}

public extension UsageProvider {
    func servePendingRefresh() async -> Bool { false }
    func pollRound() async throws { _ = try await status(refresh: true) }
}

public actor UsageService: UsageProvider {
    private var refreshTask: Task<Void, Error>?
    private var sourceErrors: [String: AccountReadError] = [:]
    private var refreshingIDs: Set<String> = []
    private let home: URL
    private var policy: Policy
    private let policyFile: URL?
    private let store: SnapshotStore
    private let runner: any ProcessRunner
    private let environment: [String: String]
    private let clock: @Sendable () -> Date
    private let pollLock: PollLock?

    /// - Parameter pollLock: When set, only the process holding it reads quota; the others serve the
    ///   shared store. Without a lock the service always polls, as a single embedded process does.
    public init(home: URL, policy: Policy, store: SnapshotStore, runner: any ProcessRunner,
                environment: [String: String], clock: @escaping @Sendable () -> Date = Date.init,
                policyFile: URL? = nil, pollLock: PollLock? = nil) {
        self.home = home; self.policy = policy; self.store = store; self.runner = runner
        self.environment = environment; self.clock = clock
        self.policyFile = policyFile; self.pollLock = pollLock
    }

    /// Builds cached status. Only explicit refresh may launch a Claude probe, and only in the polling
    /// process. A refresh in any other process leaves a request in the store for the poller.
    public func status(refresh: Bool = false) async throws -> StatusDocument {
        reloadPolicy()
        let targets = try discoveredTargets()
        if refresh { try await refreshOrRequest(targets) }
        else if refreshTask == nil, !isPollerElsewhere { try await refreshReadings(targets.filter { $0.provider != .claude }) }
        reloadPolicy()
        return try cachedStatus()
    }

    /// Serves a refresh another process requested through the store. Does nothing in a process that does not poll.
    /// Returns whether it found a request and took readings for it, even when some account failed, because the
    /// store may then hold new readings.
    @discardableResult
    public func servePendingRefresh() async -> Bool {
        guard pollLock?.isHolding ?? true else { return false }
        var isServed = false
        do {
            guard try store.hasRefreshRequest() else { return false }
            isServed = true
            _ = try await status(refresh: true)
        } catch { if !Task.isCancelled { FileHandle.standardError.write(Data("requested quota refresh failed\n".utf8)) } }
        return isServed
    }

    /// Reads quota when this process polls or can take the poll over. A scheduled round in a process that
    /// does not poll does nothing, so rounds of several processes never add readings.
    public func pollRound() async throws {
        guard pollLock?.tryAcquire() ?? true else { return }
        reloadPolicy()
        try await poll(discoveredTargets())
    }

    private func discoveredTargets() throws -> [Target] {
        let book = try AccountBook.load(AccountBook.fileURL(home: home))
        return try TargetDiscovery.discover(home: home, accounts: policy.accounts, environment: environment, book: book)
    }

    /// Writes the accounts discovery finds into the shared book, so a folder that later disappears stays
    /// listed and can be removed. Only the polling process does this.
    private func recordAccounts() throws {
        try AccountBookFile(url: AccountBook.fileURL(home: home)).update { book in
            book.reconcile(with: try TargetDiscovery.catalogue(home: home, accounts: policy.accounts,
                environment: environment, book: book))
            book.adoptLabels(of: policy.accounts, home: home)
        }
    }

    private var isPollerElsewhere: Bool { pollLock.map { !$0.isHolding && $0.isHeldElsewhere() } ?? false }

    private var poller: Poller {
        guard let pollLock else { return .thisProcess }
        if pollLock.isHolding { return .thisProcess }
        return pollLock.isHeldElsewhere() ? .otherProcess : .nobody
    }

    private func refreshOrRequest(_ targets: [Target]) async throws {
        guard pollLock?.tryAcquire() ?? true else {
            try store.requestRefresh(at: clock())
            return
        }
        try await poll(targets)
    }

    private func poll(_ targets: [Target]) async throws {
        try store.takeRefreshRequest()
        try recordAccounts()
        try await refreshReadings(targets)
    }

    private func cachedStatus() throws -> StatusDocument {
        let targets = try discoveredTargets()
        let now = clock()
        var accounts: [AccountStatus] = [], history: [String: [HistoryPoint]] = [:]
        for target in targets {
            let ids = TargetDiscovery.historyIDs(for: target, home: home, accounts: policy.accounts)
            let cached = try ids.compactMap { try store.latest($0) }
            let reading = mergedReading(cached, now: now)
            let snapshot = reading.snapshot
            let local = try snapshot?.sevenDay.resetsAt.map { try mergedHistory(ids, resetsAt: $0) } ?? []
            let byTime = Dictionary(local.map { ($0.at, $0) }, uniquingKeysWith: { _, last in last })
            let start = snapshot?.sevenDay.resetsAt?.addingTimeInterval(-Forecaster.week) ?? now
            let points = Forecaster.settled(byTime.values.filter { $0.at >= start && $0.at <= now }).sorted { $0.at < $1.at }
            accounts.append(try account(target, snapshot: snapshot, history: points, now: now, incomplete: reading.incomplete))
            history[target.id] = thinned(points)
        }
        return StatusDocument(generatedAt: now, poller: poller, accounts: accounts, history: history)
    }
    /// Evaluates policy against cached readings without spending quota.
    public func advise(_ request: AdviceRequest) async throws -> Advice {
        let document = try await status()
        return Advisor.advise(request, document: document, policy: policy)
    }

    /// Returns the current validated polling interval, including saved settings changes.
    public func pollingMinutes() -> Int {
        reloadPolicy()
        return policy.pollMinutes
    }

    private func reloadPolicy() {
        guard let policyFile else { return }
        do { policy = try Policy.load(policyFile, home: home) }
        catch { FileHandle.standardError.write(Data("invalid policy update; keeping the last valid policy\n".utf8)) }
    }

    private func refreshReadings(_ targets: [Target]) async throws {
        guard !targets.isEmpty else { return }
        if let refreshTask {
            let covered = refreshingIDs
            try await waitForRefresh(refreshTask)
            try await refreshReadings(targets.filter { !covered.contains($0.id) })
            return
        }
        let reader = SourceReadings(home: home, runner: runner, environment: environment, clock: clock)
        refreshingIDs = Set(targets.map(\.id))
        let task = Task {
            defer { refreshTask = nil; refreshingIDs = [] }
            let readings = await reader.read(targets)
            try Task.checkCancellation()
            for (id, snapshots, error) in readings {
                sourceErrors[id] = error
                if snapshots.isEmpty { try store.markFailed(id, at: clock(), reason: error) }
                let backfill = try await backfillPoints(targets.first { $0.id == id }, snapshots: snapshots)
                for snapshot in snapshots { try store.record(snapshot, estimated: snapshot == snapshots.last ? backfill : []) }
            }
        }
        refreshTask = task
        try await waitForRefresh(task)
    }

    /// Estimates the current week for an account that has never been read, from its own transcripts.
    /// Runs once per account: any earlier real reading under the account or its aliases skips it.
    private func backfillPoints(_ target: Target?, snapshots: [Snapshot]) async throws -> [HistoryPoint] {
        guard let target, target.provider != .grok, snapshots.count == 1, let anchor = snapshots.first, let weekReset = anchor.sevenDay.resetsAt,
              anchor.at > weekReset.addingTimeInterval(-Forecaster.week) else { return [] }
        let ids = TargetDiscovery.historyIDs(for: target, home: home, accounts: policy.accounts)
        guard try ids.allSatisfy({ try !store.hasReadings($0) }) else { return [] }
        let window = DateInterval(start: weekReset.addingTimeInterval(-Forecaster.week), end: anchor.at)
        let folder = target.configDir.appendingPathComponent(target.provider == .claude ? "projects" : "sessions")
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Backfill.points(transcripts: folder, window: window, anchor: anchor))
            }
        }
    }

    private func waitForRefresh(_ task: Task<Void, Error>) async throws {
        try await withTaskCancellationHandler {
            try await task.value
            try Task.checkCancellation()
        } onCancel: { task.cancel() }
    }

    private func account(_ target: Target, snapshot: Snapshot?, history: [HistoryPoint], now: Date, incomplete: Bool) throws -> AccountStatus {
        let five = visible(snapshot?.fiveHour, now: now), week = visible(snapshot?.sevenDay, now: now)
        let forecast = Forecaster.forecast(history, resetsAt: week.resetsAt, now: now)
        let configuration = policy.accounts.first { $0.id == target.id }
        let old = target.provider == .claude && snapshot.map { now.timeIntervalSince($0.at) > Double(policy.pollMinutes * 60) } == true
        let failed = try store.hasFailure(target.id, after: snapshot?.at)
        let error = try sourceErrors[target.id] ?? store.failureReason(target.id, after: snapshot?.at)
        let aliases = policy.accounts.filter {
            $0.provider == target.provider && $0.configDir.path != target.configDir.path
                && $0.configDir.resolvingSymlinksInPath() == target.configDir.resolvingSymlinksInPath()
        }.map { $0.configDir.path }
        return AccountStatus(id: target.id, label: target.label, provider: target.provider, configDir: target.configDir.path,
            registered: target.registered, aliases: aliases, plan: snapshot?.plan, fiveHour: five, sevenDay: week, forecast: forecast,
            source: snapshot.map { _ in target.provider == .claude ? "probe" : target.provider == .codex ? "codex-log" : "grok-cache" },
            stale: snapshot == nil || old || failed || incomplete || error != nil, error: error, asOf: snapshot?.at,
            targetLow: configuration?.targetLow ?? 75, targetHigh: configuration?.targetHigh ?? 100)
    }

    private func mergedReading(_ readings: [Snapshot], now: Date) -> (snapshot: Snapshot?, incomplete: Bool) {
        guard let newest = readings.max(by: { $0.at < $1.at }) else { return (nil, false) }
        let five = latestWindow(readings, \.fiveHour), week = latestWindow(readings, \.sevenDay)
        let contributing = [five, week].compactMap { reading -> Date? in
            guard let reading, (reading.0.resetsAt ?? .distantPast) > now else { return nil }
            return reading.1
        }
        let at = ([newest.at] + contributing).min() ?? newest.at
        return (Snapshot(account: newest.account, at: at, plan: newest.plan,
            fiveHour: five?.0 ?? UsageWindow(), sevenDay: week?.0 ?? UsageWindow()), at < newest.at)
    }

    private func latestWindow(_ readings: [Snapshot], _ key: KeyPath<Snapshot, UsageWindow>) -> (UsageWindow, Date)? {
        readings.filter { $0[keyPath: key].pct != nil && $0[keyPath: key].resetsAt != nil }
            .max { $0.at < $1.at }.map { ($0[keyPath: key], $0.at) }
    }

    private func visible(_ window: UsageWindow?, now: Date) -> UsageWindow {
        guard let window, window.pct != nil, let reset = window.resetsAt, reset > now else { return UsageWindow() }
        return window
    }

    private func mergedHistory(_ ids: [String], resetsAt: Date) throws -> [HistoryPoint] {
        var byTimestamp: [Date: HistoryPoint] = [:]
        // The canonical account wins when two aliases recorded the same timestamp.
        for id in ids.reversed() {
            for point in try store.windowHistory(id, resetsAt: resetsAt) { byTimestamp[point.at] = point }
        }
        return byTimestamp.values.sorted { $0.at < $1.at }
    }

    private func thinned(_ points: [HistoryPoint]) -> [HistoryPoint] {
        let step = max(1, (points.count + 199) / 200)
        var result = stride(from: 0, to: points.count, by: step).map { points[$0] }
        if let last = points.last, result.last != last { result.append(last) }
        return result
    }
}
