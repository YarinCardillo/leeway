import Foundation
import Testing
@testable import LeewayCore

let now = Date(timeIntervalSince1970: 1_793_653_200)
let hour: TimeInterval = 3600
let reset = now.addingTimeInterval(34 * hour)

func hourly(_ values: [Double], end: Date = now) -> [HistoryPoint] {
    values.enumerated().map { HistoryPoint(at: end.addingTimeInterval(-Double(values.count - 1 - $0.offset) * hour), pct: $0.element) }
}

@Test func forecastWithoutHistoryOrResetHasNoForecast() {
    #expect(Forecaster.forecast([], resetsAt: reset, now: now).confidence == .none)
    #expect(Forecaster.forecast(hourly([50]), resetsAt: nil, now: now).nextRoundPct == nil)
}

@Test func risingTrendIncludesRoundCost() {
    let result = Forecaster.forecast(hourly([80, 82, 84, 86, 88, 90, 92]), resetsAt: reset, now: now)
    #expect(result.sevenDayPctAtReset == 160)
    #expect(result.nextRoundPct == 102)
    #expect(result.confidence == .high)
    #expect(result.exhaustsAt == now.addingTimeInterval(4 * hour))
}

@Test func flatAndSingleSamplesRetainRoundFloorWithoutRecentTrend() {
    let flat = Forecaster.forecast(hourly([40, 40, 40]), resetsAt: reset, now: now)
    #expect(flat.sevenDayPctAtReset == nil)
    #expect(flat.nextRoundPct == 41)
    #expect(flat.exhaustsAt == nil)
    #expect(flat.confidence == .low)
    #expect(Forecaster.forecast(hourly([94]), resetsAt: reset, now: now).confidence == .low)
}

@Test func shortObservedSpanHasNoRecentPaceAndNegativeSlopeNeverLowersUsage() {
    let old = Forecaster.forecast(hourly([50, 52], end: now.addingTimeInterval(-8 * hour)), resetsAt: reset, now: now)
    #expect(old.sevenDayPctAtReset == nil)
    #expect(old.confidence == .low)
    #expect(Forecaster.forecast(hourly([60, 59, 58, 57, 56, 55, 50]), resetsAt: reset, now: now).sevenDayPctAtReset == 50)
}

@Test func uiForecastUsesOnlyWeekAverageForShortObservedSpan() {
    let end = now.addingTimeInterval(84 * hour)
    let result = Forecaster.forecast(hourly([20, 30, 40]), resetsAt: end, now: now)
    #expect(result.averagePctAtReset == 80)
    #expect(result.recentPctAtReset == nil)
    #expect(result.rangeLow == 80)
    #expect(result.rangeHigh == 80)
}

@Test func expiredResetHasNoForecastAndDuplicateTimesHaveNoRecentPace() {
    #expect(Forecaster.forecast(hourly([50]), resetsAt: now, now: now).confidence == .none)
    let points = [HistoryPoint(at: now, pct: 10), HistoryPoint(at: now, pct: 20)]
    #expect(Forecaster.forecast(points, resetsAt: reset, now: now).sevenDayPctAtReset == nil)
}

@Test func riskUsesTargetRangeOverlap() {
    #expect(AccountRisk.evaluate(low: 70, high: 84, targetLow: 75, targetHigh: 100) == .onTarget)
    #expect(AccountRisk.evaluate(low: 30, high: 70, targetLow: 75, targetHigh: 100) == .under)
    #expect(AccountRisk.evaluate(low: 101, high: 110, targetLow: 75, targetHigh: 100) == .over)
}
