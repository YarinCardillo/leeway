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

@Test func publicVersionInfoEncodesTheContractFields() throws {
    let raw = try #require(JSONSerialization.jsonObject(with: JSONCodec.encoder().encode(VersionInfo.current)) as? [String: Any])
    #expect(raw["store_schema"] as? Int == SnapshotStore.schemaVersion)
    #expect(raw["status_schema"] as? Int == StatusDocument.currentSchemaVersion)
    #expect(try LeewayCLI.runVersion(["--json"]).contains("\"accounts_schema\":1"))
}

@Test func publicHistoryPointCanBeBuiltAsEstimated() {
    #expect(HistoryPoint(at: Date(timeIntervalSince1970: 0), pct: 1).estimated == false)
    #expect(HistoryPoint(at: Date(timeIntervalSince1970: 0), pct: 1, estimated: true).estimated)
}
