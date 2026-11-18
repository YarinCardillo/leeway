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

private func estimated(_ values: [Double], end: Date) -> [HistoryPoint] {
    hourly(values, end: end).map { HistoryPoint(at: $0.at, pct: $0.pct, estimated: true) }
}

@Test func forecast_BackfillPlusOneRealReading_IsProduced() {
    let backfill = estimated([4, 8, 12, 16, 20, 24, 28], end: now.addingTimeInterval(-hour))
    let history = backfill + [HistoryPoint(at: now, pct: 30)]
    let result = Forecaster.forecast(history, resetsAt: reset, now: now)
    #expect(result.confidence != .none)
    #expect(result.recentPctAtReset != nil)
    #expect(result.averagePctAtReset != nil)
    #expect(Forecaster.forecast(backfill, resetsAt: reset, now: now).confidence != .none)
}

@Test func forecast_ThreeRealReadings_DropTheEstimatedPoints() {
    let backfill = estimated([10, 20, 30, 40, 50, 60], end: now.addingTimeInterval(-3 * hour))
    let real = [HistoryPoint(at: now.addingTimeInterval(-2 * hour), pct: 61), HistoryPoint(at: now.addingTimeInterval(-hour), pct: 62),
                HistoryPoint(at: now, pct: 63)]
    #expect(Forecaster.forecast(backfill + real, resetsAt: reset, now: now) == Forecaster.forecast(real, resetsAt: reset, now: now))
    let twoReal = Array(real.suffix(2))
    #expect(Forecaster.forecast(backfill + twoReal, resetsAt: reset, now: now) != Forecaster.forecast(twoReal, resetsAt: reset, now: now))
}

@Test func historyPoint_EstimatedPointsCarryAThirdJsonElementAndRealOnesStayPairs() throws {
    let points = [HistoryPoint(at: now, pct: 10), HistoryPoint(at: now.addingTimeInterval(60), pct: 11, estimated: true)]
    let raw = try #require(JSONSerialization.jsonObject(with: JSONCodec.encoder().encode(points)) as? [[Any]])
    #expect(raw[0].count == 2)
    #expect(raw[1].count == 3)
    #expect(raw[1][2] as? Bool == true)
    #expect(try JSONCodec.decoder().decode([HistoryPoint].self, from: JSONCodec.encoder().encode(points)) == points)
}

@Test func historyPoint_AnOlderPairDecodesAsReal() throws {
    let text = "[[\"2026-11-02T09:00:00Z\", 12.5]]"
    let decoded = try JSONCodec.decoder().decode([HistoryPoint].self, from: Data(text.utf8))
    #expect(decoded.first?.estimated == false)
    #expect(decoded.first?.pct == 12.5)
}
