import Foundation

/// Reads the weekly usage Grok Bot caches for its own usage view. Never launches Grok Bot, never opens its
/// secrets, and sends no request. Grok Bot and Cursor share one included weekly allowance, so the reading covers both.
public enum GrokBotReader {
    static let defaultFolder = "Library/Application Support/Grok Bot"
    private static let persistence = "sand-client-persistence"
    private static let cacheSuffix = ".weekly-usage.cache"
    private static let maxBytes = 64 * 1024
    /// Grok Bot writes the cache on this Mac, so a reading ahead of the clock by more than this is not trusted.
    private static let clockSkew: TimeInterval = 60
    /// The included allowance is weekly: a reset further than a week (plus an hour of slack) after the reading is not it.
    private static let longestWindow: TimeInterval = 7 * 86400 + 3600
    /// Plan names are short labels; anything longer (counted in UTF-8 bytes, so combining marks count) is not stored.
    private static let maxPlanBytes = 64

    /// Returns the newest cached reading across the signed-in accounts in `home`, the Grok Bot data folder.
    /// A slice that cannot be read safely is skipped, so it cannot hide a readable sibling.
    public static func read(home: URL, account: String, now: Date) throws -> Snapshot? {
        let folder = home.appendingPathComponent(persistence)
        guard isDirectory(folder) else { return nil }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "blob" && key($0)?.hasSuffix(cacheSuffix) == true }
            .compactMap { contents($0).flatMap { parse($0, account: account, now: now) } }
            .max { $0.at < $1.at }
    }

    /// The bytes of a regular file of at most `maxBytes`. The checks run on the opened descriptor, so a symlink,
    /// a FIFO, or a file replaced or grown after the listing is never read past the limit.
    static func contents(_ file: URL) -> Data? {
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_size <= maxBytes,
              let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes else { return nil }
        return data
    }

    /// Grok Bot names each persisted slice after its key, base32-encoded without padding.
    static func key(_ file: URL) -> String? {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var bits = 0, value = 0, bytes: [UInt8] = []
        for character in file.deletingPathExtension().lastPathComponent.lowercased() {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            value = (value << 5) | index; bits += 5
            if bits >= 8 { bits -= 8; bytes.append(UInt8((value >> bits) & 0xFF)) }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    static func parse(_ data: Data, account: String, now: Date) -> Snapshot? {
        guard let object = jsonObject(data), let value = object["value"] as? [String: Any], value["kind"] as? String == "present",
              let reading = value["reading"] as? [String: Any], let usage = reading["usage"] as? [String: Any],
              let at = milliseconds(reading["readAtMs"]), at <= now.addingTimeInterval(clockSkew),
              let reset = milliseconds(usage["nextResetMs"]), reset > at, reset <= at.addingTimeInterval(longestWindow),
              let used = quotaNumber(usage["percentUsed"]), used >= 0 else { return nil }
        let label = (usage["unifiedPlanName"] as? String) ?? (usage["grokPlanLabel"] as? String)
        let plan = label.flatMap { $0.utf8.count <= maxPlanBytes ? $0 : nil }
        // On-demand spend continues past the included allowance; the included window itself tops out at 100%.
        return Snapshot(account: account, at: at, plan: plan, sevenDay: UsageWindow(pct: rounded(min(used, 100)), resetsAt: reset))
    }

    private static func milliseconds(_ raw: Any?) -> Date? {
        quotaNumber(raw).flatMap { quotaDate(NSNumber(value: $0 / 1000)) }
    }
}
