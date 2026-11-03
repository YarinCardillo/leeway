import Foundation

public enum CodexReader {
    private static let newestFiles = 6
    private static let tailBytes: UInt64 = 512 * 1024

    /// Reads only rate-limit records from up to six recent rollout tails. Never launches Codex.
    public static func read(home: URL, account: String) throws -> Snapshot? {
        try history(home: home, account: account).last
    }

    /// Returns all valid rate-limit events from the same bounded rollout tails, oldest first.
    public static func history(home: URL, account: String) throws -> [Snapshot] {
        let sessions = home.appendingPathComponent("sessions")
        guard FileManager.default.fileExists(atPath: sessions.path) else { return [] }
        guard let files = FileManager.default.enumerator(at: sessions,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]) else { return [] }
        var candidates: [(URL, Date)] = []
        for case let file as URL in files where file.lastPathComponent.hasPrefix("rollout-") && file.pathExtension == "jsonl" {
            let info = try file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
            if info.isRegularFile == true, info.isSymbolicLink != true {
                candidates.append((file, info.contentModificationDate ?? .distantPast))
            }
        }
        let recent = candidates.sorted { $0.1 > $1.1 }.prefix(newestFiles)
        return try recent.flatMap { try limits($0.0, account: account) }.sorted { $0.at < $1.at }
    }

    private static func limits(_ file: URL, account: String) throws -> [Snapshot] {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        try handle.seek(toOffset: end > tailBytes ? end - tailBytes : 0)
        let data = try handle.readToEnd() ?? Data()
        return data.split(separator: 10).compactMap { line in
            guard line.range(of: Data("rate_limits".utf8)) != nil else { return nil }
            return parse(Data(line), account: account)
        }
    }

    private static func parse(_ line: Data, account: String) -> Snapshot? {
        guard let object = jsonObject(line), let timestamp = object["timestamp"] as? String, let at = moment(timestamp),
              let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
              let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        var windows: [Double: UsageWindow] = [:]
        for key in ["primary", "secondary"] {
            guard let raw = limits[key] as? [String: Any], let minutes = quotaNumber(raw["window_minutes"]),
                  let used = quotaNumber(raw["used_percent"]), (0...100).contains(used),
                  let reset = quotaDate(raw["resets_at"]) else { continue }
            windows[minutes] = UsageWindow(pct: rounded(used), resetsAt: reset)
        }
        guard windows[300] != nil || windows[10080] != nil else { return nil }
        return Snapshot(account: account, at: at, plan: limits["plan_type"] as? String,
            fiveHour: windows[300] ?? UsageWindow(), sevenDay: windows[10080] ?? UsageWindow())
    }
}
