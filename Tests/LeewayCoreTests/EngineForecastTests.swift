import Foundation
import Testing
@testable import LeewayCore

// Expected values use the engine's endpoint pace, not a fit over sample density.
private func fixture(_ samples: [(Double, Double)]) -> [HistoryPoint] {
    samples.map { HistoryPoint(at: now.addingTimeInterval($0.0 * hour), pct: $0.1) }
}

@Test func engineForecast_LastHoursBurst_UsesWholeRecentWindow() {
    let points = fixture([(-24, 2), (-2, 2), (-1, 8), (0, 13)])
    let result = Forecaster.forecast(points, resetsAt: reset, now: now)
    #expect(result.averagePctAtReset == 16.3)
    #expect(result.recentPctAtReset == 28.6)
    #expect(result.sevenDayPctAtReset == result.recentPctAtReset)
    #expect(result.rangeLow == 16.3)
    #expect(result.rangeHigh == 28.6)
    #expect(AccountRisk.evaluate(low: result.rangeLow, high: result.rangeHigh, targetLow: 75, targetHigh: 100) == .under)
}

@Test func engineForecast_SparseReadings_UsesFirstSampleInside24Hours() {
    let points = fixture([(-48, 1), (-25, 2), (-20, 5), (-2, 13)])
    let result = Forecaster.forecast(points, resetsAt: reset, now: now)
    #expect(result.averagePctAtReset == 16.3)
    #expect(result.recentPctAtReset == 28.1)
    #expect(result.sevenDayPctAtReset == 28.1)
}

@Test func engineForecast_LessThanSixHours_UsesOnlyWeeklyAverage() {
    let result = Forecaster.forecast(fixture([(-3, 10), (-1, 12), (0, 13)]), resetsAt: reset, now: now)
    #expect(result.averagePctAtReset == 16.3)
    #expect(result.recentPctAtReset == nil)
    #expect(result.sevenDayPctAtReset == nil)
}

@Test func engineForecast_ResetInsideRecentWindow_ExcludesPriorWeek() {
    let result = Forecaster.forecast(fixture([(-7, 99), (-5, 1), (-1, 2), (0, 3)]),
                                     resetsAt: now.addingTimeInterval(162 * hour), now: now)
    #expect(result.averagePctAtReset == 84)
    #expect(result.recentPctAtReset == nil)
    #expect(result.sevenDayPctAtReset == nil)
}

@Test func engineForecast_OnlyOneWeeklyReading_HasNoProjection() {
    let result = Forecaster.forecast(fixture([(0, 13)]), resetsAt: reset, now: now)
    #expect(result.averagePctAtReset == nil)
    #expect(result.recentPctAtReset == nil)
    #expect(result.rangeHigh == nil)
}

@Test func engineForecast_OnlyOneRecentReading_DoesNotInventFlatTrend() {
    let result = Forecaster.forecast(fixture([(-25, 5), (0, 13)]), resetsAt: reset, now: now)
    #expect(result.averagePctAtReset == 16.3)
    #expect(result.recentPctAtReset == nil)
    #expect(result.rangeLow == 16.3)
    #expect(result.rangeHigh == 16.3)
}

@Test func engineForecast_StaleEndpoints_UsesObservedPace() {
    let result = Forecaster.forecast(fixture([(-20, 10), (-8, 13)]), resetsAt: reset, now: now)
    #expect(result.recentPctAtReset == 21.5)
    #expect(result.sevenDayPctAtReset == 21.5)
}

@Test func engineForecast_UsageDecrease_ClampsToUsed() {
    let result = Forecaster.forecast(fixture([(-24, 20), (0, 13)]), resetsAt: reset, now: now)
    #expect(result.recentPctAtReset == 13)
    #expect(result.averagePctAtReset == 16.3)
}
