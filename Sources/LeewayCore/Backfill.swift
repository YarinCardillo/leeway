import Foundation

/// Builds an estimated weekly history for an account that has no readings yet, from its own
/// session transcripts. The shape comes from token counts; the scale comes from one real reading.
public enum Backfill {
    private static let bucket: TimeInterval = 3600

    /// Estimates the current window's usage curve.
    ///
    /// Tokens are summed per hour from `transcripts` (a Claude `projects` folder or a Codex `sessions`
    /// folder), accumulated, and scaled so the last point equals the anchor's real seven-day utilisation.
    /// Every point is marked estimated. Returns an empty list when there is nothing to scale: no
    /// transcripts in the window, or an anchor without a positive weekly percentage.
    ///
    /// - Parameters:
    ///   - transcripts: Root folder searched recursively for `.jsonl` transcripts.
    ///   - window: The current weekly window; only turns inside it are used.
    ///   - anchor: The first real reading, which fixes the scale.
    public static func points(transcripts: URL, window: DateInterval, anchor: Snapshot) -> [HistoryPoint] {
        guard let target = anchor.sevenDay.pct, target > 0 else { return [] }
        let hourly = cumulativeByHour(TranscriptUsage.events(in: transcripts, window: window))
        guard let total = hourly.last?.tokens, total > 0 else { return [] }
        let curve = hourly.map { HistoryPoint(at: $0.at, pct: rounded(target * $0.tokens / total), estimated: true) }
        let scaled = curve.dropLast() + [HistoryPoint(at: hourly[hourly.count - 1].at, pct: target, estimated: true)]
        return scaled.filter { $0.pct > 0 }
    }

    /// One entry per clock hour with activity: the time of its last turn and the tokens used up to then.
    private static func cumulativeByHour(_ events: [UsageEvent]) -> [UsageEvent] {
        var result: [UsageEvent] = []
        var running = 0.0
        var currentHour: Int?
        for event in events {
            running += event.tokens
            let hour = Int((event.at.timeIntervalSince1970 / bucket).rounded(.down))
            let entry = UsageEvent(at: event.at, tokens: running)
            if hour == currentHour { result[result.count - 1] = entry } else { result.append(entry) }
            currentHour = hour
        }
        return result
    }
}
