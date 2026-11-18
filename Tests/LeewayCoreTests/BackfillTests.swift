import Foundation
import Testing
@testable import LeewayCore

private func isoString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func claudeLine(_ at: Date, input: Int = 100, output: Int = 50, created: Int = 0, id: String? = nil) -> String {
    let identifier = id.map { "\"id\":\"\($0)\"," } ?? ""
    return "{\"type\":\"assistant\",\"timestamp\":\"\(isoString(at))\",\"message\":{\(identifier)\"role\":\"assistant\","
        + "\"content\":[{\"type\":\"text\",\"text\":\"fixture reply\"}],\"usage\":{\"input_tokens\":\(input),"
        + "\"output_tokens\":\(output),\"cache_creation_input_tokens\":\(created),\"cache_read_input_tokens\":9999}}}"
}

private func codexLine(_ at: Date, input: Int = 100, output: Int = 50) -> String {
    "{\"timestamp\":\"\(isoString(at))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
        + "\"info\":{\"last_token_usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output)}}}}"
}

private func write(_ lines: [String], to file: URL) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
}

private let weekStart = reset.addingTimeInterval(-Forecaster.week)
private let currentWindow = DateInterval(start: weekStart, end: now)

private func anchor(pct: Double = 30) -> Snapshot {
    Snapshot(account: "fixture", at: now, sevenDay: UsageWindow(pct: pct, resetsAt: reset))
}

@Test func backfill_ClaudeTranscripts_CurveIsMonotonicEndsAtTheAnchorAndStaysInTheWindow() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try write([
        claudeLine(weekStart.addingTimeInterval(-3 * hour)),
        claudeLine(weekStart.addingTimeInterval(2 * hour)),
        claudeLine(weekStart.addingTimeInterval(2.5 * hour), input: 300),
        claudeLine(now.addingTimeInterval(-30 * hour), output: 500),
    ], to: root.appendingPathComponent("-fixture-project/session-a.jsonl"))
    try write([claudeLine(now.addingTimeInterval(-2 * hour)), "not json at all", "{\"type\":\"summary\"}",
               claudeLine(now.addingTimeInterval(1 * hour))],
        to: root.appendingPathComponent("-other-project/nested/session-b.jsonl"))
    let points = Backfill.points(transcripts: root, window: currentWindow, anchor: anchor())
    #expect(points.count >= 3)
    #expect(points.allSatisfy { $0.estimated })
    #expect(points.allSatisfy { currentWindow.start <= $0.at && $0.at <= currentWindow.end })
    #expect(zip(points, points.dropFirst()).allSatisfy { $0.at < $1.at && $0.pct <= $1.pct })
    #expect(points.last?.pct == 30)
    #expect(points.allSatisfy { $0.pct > 0 })
}

@Test func backfill_CacheReadsAreNotCountedAndRepeatedMessageIdsCountOnce() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = now.addingTimeInterval(-50 * hour), second = now.addingTimeInterval(-10 * hour)
    try write([claudeLine(first, input: 100, output: 0, id: "m1"), claudeLine(first.addingTimeInterval(1), input: 100, output: 0, id: "m1"),
               claudeLine(second, input: 100, output: 0, id: "m2")],
        to: root.appendingPathComponent("p/s.jsonl"))
    try write([claudeLine(first, input: 100, output: 0, id: "m1")], to: root.appendingPathComponent("p/resumed.jsonl"))
    let points = Backfill.points(transcripts: root, window: currentWindow, anchor: anchor(pct: 40))
    #expect(points.map(\.pct) == [20, 40])
}

@Test func backfill_CodexRollouts_UseTheSameShape() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try write([codexLine(now.addingTimeInterval(-60 * hour)), "{\"type\":\"session_meta\"}", codexLine(now.addingTimeInterval(-20 * hour), input: 250),
               codexLine(now.addingTimeInterval(-5 * hour))],
        to: root.appendingPathComponent("2026/11/16/rollout-fixture.jsonl"))
    let points = Backfill.points(transcripts: root, window: currentWindow, anchor: anchor(pct: 12))
    #expect(points.count == 3)
    #expect(points.last?.pct == 12)
    #expect(points.allSatisfy { $0.estimated })
}

@Test func backfill_NothingToScale_IsEmpty() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(Backfill.points(transcripts: root.appendingPathComponent("missing"), window: currentWindow, anchor: anchor()).isEmpty)
    #expect(Backfill.points(transcripts: root, window: currentWindow, anchor: anchor()).isEmpty)
    try write([claudeLine(now.addingTimeInterval(-hour))], to: root.appendingPathComponent("p/s.jsonl"))
    #expect(Backfill.points(transcripts: root, window: currentWindow, anchor: anchor(pct: 0)).isEmpty)
    let noWeek = Snapshot(account: "fixture", at: now)
    #expect(Backfill.points(transcripts: root, window: currentWindow, anchor: noWeek).isEmpty)
}

@Test func backfill_SeveralPointsInOneHour_CollapseIntoOne() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let base = now.addingTimeInterval(-20 * hour)
    try write((0..<10).map { claudeLine(base.addingTimeInterval(Double($0) * 60)) }, to: root.appendingPathComponent("p/s.jsonl"))
    #expect(Backfill.points(transcripts: root, window: currentWindow, anchor: anchor()).count == 1)
}
