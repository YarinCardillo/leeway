import Foundation

/// One assistant turn's token cost at the moment it happened.
struct UsageEvent: Equatable, Sendable {
    let at: Date
    let tokens: Double
}

/// Reads timestamps and token counts, and nothing else, from Claude and Codex session transcripts.
enum TranscriptUsage {
    private static let claudeMarker = Data("\"usage\"".utf8)
    private static let codexMarker = Data("last_token_usage".utf8)
    private static let countedKeys = ["input_tokens", "output_tokens", "cache_creation_input_tokens"]

    /// Returns the turns inside `window` found in every `.jsonl` file under `root`, oldest first.
    /// A Claude message that appears more than once (streamed or resumed sessions) counts once.
    static func events(in root: URL, window: DateInterval) -> [UsageEvent] {
        var unnamed: [UsageEvent] = []
        var named: [String: UsageEvent] = [:]
        for file in transcriptFiles(in: root, since: window.start) {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            for line in data.split(separator: 10) {
                guard let (identifier, event) = parse(Data(line)), window.contains(event.at) else { continue }
                guard let identifier else { unnamed.append(event); continue }
                let first = named[identifier]
                named[identifier] = UsageEvent(at: first?.at ?? event.at, tokens: max(first?.tokens ?? 0, event.tokens))
            }
        }
        return (unnamed + named.values).sorted { $0.at < $1.at }
    }

    private static func transcriptFiles(in root: URL, since start: Date) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]) else { return [] }
        var files: [URL] = []
        for case let file as URL in walker where file.pathExtension == "jsonl" {
            guard let info = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  info.isRegularFile == true, info.isSymbolicLink != true,
                  (info.contentModificationDate ?? .distantPast) >= start else { continue }
            files.append(file)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func parse(_ line: Data) -> (String?, UsageEvent)? {
        guard line.range(of: claudeMarker) != nil || line.range(of: codexMarker) != nil,
              let object = jsonObject(line), let stamp = object["timestamp"] as? String, let at = moment(stamp) else { return nil }
        let message = object["message"] as? [String: Any]
        let codex = (object["payload"] as? [String: Any]).flatMap { $0["type"] as? String == "token_count" ? $0["info"] as? [String: Any] : nil }
        guard let usage = (message?["usage"] ?? codex?["last_token_usage"]) as? [String: Any] else { return nil }
        let tokens = countedKeys.compactMap { quotaNumber(usage[$0]) }.reduce(0, +)
        return tokens > 0 ? (message?["id"] as? String, UsageEvent(at: at, tokens: tokens)) : nil
    }
}
