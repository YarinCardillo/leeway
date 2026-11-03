import Foundation
import Testing
@testable import LeewayCore

@Test(arguments: [25.0 * 60, 6 * hour - 1])
func recentPace_InsufficientObservedSpan_UsesOnlyAverage(_ span: TimeInterval) {
    let result = Forecaster.forecast([
        HistoryPoint(at: now.addingTimeInterval(-span), pct: 12), HistoryPoint(at: now, pct: 13)
    ], resetsAt: reset, now: now)
    #expect(result.averagePctAtReset == 16.3)
    #expect(result.recentPctAtReset == nil)
    #expect(result.sevenDayPctAtReset == nil)
    #expect(result.rangeLow == 16.3)
    #expect(result.rangeHigh == 16.3)
    #expect(result.exhaustsAt == nil)
    #expect(result.confidence == .low)
    #expect(AccountRisk.evaluate(low: result.rangeLow, high: result.rangeHigh, targetLow: 75, targetHigh: 100) == .under)
}

@Test func recentPace_ExactlySixHours_UsesEndpointPace() {
    let result = Forecaster.forecast([
        HistoryPoint(at: now.addingTimeInterval(-6 * hour), pct: 12), HistoryPoint(at: now, pct: 13)
    ], resetsAt: reset, now: now)
    #expect(result.averagePctAtReset == 16.3)
    #expect(result.recentPctAtReset == 18.7)
    #expect(result.rangeHigh == 18.7)
    #expect(result.confidence == .medium)
}

@Test func recentPace_OlderSamplesOutside24Hours_DoNotQualifyShortRecentSpan() {
    let result = Forecaster.forecast([
        HistoryPoint(at: now.addingTimeInterval(-25 * hour), pct: 1),
        HistoryPoint(at: now.addingTimeInterval(-hour), pct: 12), HistoryPoint(at: now, pct: 13)
    ], resetsAt: reset, now: now)
    #expect(result.recentPctAtReset == nil)
    #expect(result.rangeHigh == result.averagePctAtReset)
}

@Test func recentPace_ResetInsideSixHours_DoesNotUsePriorWeekToQualify() {
    let result = Forecaster.forecast([
        HistoryPoint(at: now.addingTimeInterval(-7 * hour), pct: 99),
        HistoryPoint(at: now.addingTimeInterval(-5 * hour), pct: 1), HistoryPoint(at: now, pct: 3)
    ], resetsAt: now.addingTimeInterval(162 * hour), now: now)
    #expect(result.averagePctAtReset == 84)
    #expect(result.recentPctAtReset == nil)
    #expect(result.rangeLow == 84)
    #expect(result.rangeHigh == 84)
    #expect(result.confidence == .low)
}
