import Foundation

/// Reads the weekly usage Grok Bot caches for its own usage view. Never launches Grok Bot, never opens its
/// secrets, and sends no request. Grok Bot and Cursor share one included weekly allowance, so the reading covers both.
public enum GrokBotReader {
    static let defaultFolder = "Library/Application Support/Grok Bot"
    private static let persistence = "sand-client-persistence"
    private static let cacheSuffix = ".weekly-usage.cache"
    private static let maxBytes = 64 * 1024

    /// Returns the newest cached reading across the signed-in accounts in `home`, the Grok Bot data folder.
    public static func read(home: URL, account: String) throws -> Snapshot? {
        let folder = home.appendingPathComponent(persistence)
        guard isDirectory(folder) else { return nil }
        let files = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        var newest: Snapshot?
        for file in files where file.pathExtension == "blob" && key(file)?.hasSuffix(cacheSuffix) == true {
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? 0) <= maxBytes,
                  let snapshot = parse(try Data(contentsOf: file), account: account) else { continue }
            if newest.map({ snapshot.at > $0.at }) ?? true { newest = snapshot }
        }
        return newest
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

    static func parse(_ data: Data, account: String) -> Snapshot? {
        guard let object = jsonObject(data), let value = object["value"] as? [String: Any], value["kind"] as? String == "present",
              let reading = value["reading"] as? [String: Any], let usage = reading["usage"] as? [String: Any],
              let at = milliseconds(reading["readAtMs"]), let reset = milliseconds(usage["nextResetMs"]),
              let used = quotaNumber(usage["percentUsed"]), used >= 0 else { return nil }
        let plan = (usage["unifiedPlanName"] as? String) ?? (usage["grokPlanLabel"] as? String)
        // On-demand spend continues past the included allowance; the included window itself tops out at 100%.
        return Snapshot(account: account, at: at, plan: plan, sevenDay: UsageWindow(pct: rounded(min(used, 100)), resetsAt: reset))
    }

    private static func milliseconds(_ raw: Any?) -> Date? {
        quotaNumber(raw).flatMap { quotaDate(NSNumber(value: $0 / 1000)) }
    }
}
