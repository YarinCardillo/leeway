import Foundation
import Testing
import LeewayCore

@Test func publicProviderForecastEncodesRangeWithoutLosingUnknownValues() throws {
    let forecast = Forecast(averagePctAtReset: 70, recentPctAtReset: 90,
        rangeLow: 70, rangeHigh: 90, nextRoundPct: 45, exhaustsAt: nil, confidence: .medium)
    let data = try JSONCodec.encoder().encode(forecast)
    let raw = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(raw["range_low"] as? Double == 70)
    #expect(raw["range_high"] as? Double == 90)
    #expect(raw["exhausts_at"] is NSNull)
}
