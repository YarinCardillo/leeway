import AppKit
import AppModel
import AppCore
import LeewayCore
import Foundation
import XCTest
@testable import LeewayPresentation

final class LocalizationTests: XCTestCase {
    private var app: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }

    func testLiteralLabels_ExistInBothLanguages() throws {
        let matcher = try NSRegularExpression(pattern: #"(?:strings\.(?:text|format)|fact)\("([^"]+)""#)
        let sources = try FileManager.default.contentsOfDirectory(at: app.appendingPathComponent("Sources/LeewayApp"), includingPropertiesForKeys: nil)
        var used = Set<String>()
        for file in sources where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in matcher.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                used.insert(String(text[Range(match.range(at: 1), in: text)!]))
            }
        }
        var previous: Set<String>?
        for language in ["en", "it"] {
            let data = try Data(contentsOf: app.appendingPathComponent("Resources/\(language).lproj/Localizable.strings"))
            let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            let keys = Set(values.keys)
            XCTAssertTrue(used.isSubset(of: keys), "\(language) missing: \(used.subtracting(keys).sorted())")
            if let previous { XCTAssertEqual(keys, previous) }
            previous = keys
        }
    }
}

extension LocalizationTests {
    private func strings(_ language: AppLanguage) -> Localizer {
        let code = language == .italian ? "it" : "en"
        let bundle = Bundle(path: app.appendingPathComponent("Resources/\(code).lproj").path)!
        return Localizer(language: language, resourceBundle: bundle)
    }

    private func account(used: Double? = 62, week: Double? = 84, recent: Double? = 97,
                         reset: Date? = Date(timeIntervalSince1970: 1804200000)) -> AccountUsage {
        AccountUsage(id: "work", name: "Work", source: "claude", weeklyUsed: used,
                     fiveHourUsed: nil, reset: reset, fiveHourReset: nil, weekForecast: week,
                     recentForecast: recent, recordedAt: nil, history: [])
    }

    func testMissingReadings_OmitUpdatedAndResetSentences() {
        let text = strings(.english)
        XCTAssertNil(text.updated(nil, isRefreshing: false))
        XCTAssertNil(text.resetFacts(account(used: nil)))
        XCTAssertEqual(text.usageFacts(account(week: nil)), "62% now, forecast unavailable, target 75-100%")
        XCTAssertEqual(text.menuBarTitle(account(week: nil)), "Work 62%")
        XCTAssertEqual(text.resetFacts(account(reset: nil)), "Reset time unknown")
        XCTAssertFalse(text.headline(account(week: nil)).contains("Unavailable"))
    }

    func testNoReading_UsesReasonOrActionableFallback() {
        let text = strings(.english)
        var value = account(used: nil)
        XCTAssertTrue(text.usageFacts(value).contains("Check that Claude Code or Codex is signed in"))
        value.error = .timeout
        XCTAssertEqual(text.usageFacts(value), "Reading timed out")
    }

    func testSourceErrors_LocalizedWithAndWithoutLastReading() {
        let english = ["CLI unavailable", "Reading timed out", "Sign in required", "Invalid quota output"]
        let italian = ["CLI non disponibile", "Lettura scaduta", "Accesso richiesto", "Dati quota non validi"]
        for (index, reason) in AccountReadError.allCases.enumerated() {
            for used in [Double(62), nil] {
                var value = account(used: used)
                value.error = reason
                XCTAssertEqual(strings(.english).readError(value), english[index])
                XCTAssertEqual(strings(.italian).readError(value), italian[index])
                XCTAssertTrue(strings(.english).menuCaption(value).contains(english[index]))
            }
        }
    }

    func testDetailSourceError_IsNotRepeatedWithoutReading() {
        var missing = account(used: nil)
        missing.error = .timeout
        XCTAssertEqual(strings(.english).usageFacts(missing), "Reading timed out")
        XCTAssertNil(strings(.english).detailReadError(missing))
        var retained = account()
        retained.error = .timeout
        XCTAssertEqual(strings(.english).detailReadError(retained), "Reading timed out")
    }

    func testForecasts_UseCompactLocalizedRangeAndEqualValueHeadline() {
        XCTAssertEqual(strings(.english).usageFacts(account()), "62% now, 84-97% at reset, target 75-100%")
        XCTAssertEqual(strings(.italian).usageFacts(account()), "62% ora, 84-97% al reset, target 75-100%")
        XCTAssertTrue(strings(.english).headline(account(recent: 84)).hasPrefix("Lands at 84%"))
        XCTAssertTrue(strings(.italian).headline(account(recent: 84)).contains("sarai all’84%"))
    }

    func testMenuBarSpeech_NamesUsedForecastAndStaleness() {
        let text = strings(.english)
        var value = account()
        value.isStale = true
        let spoken = text.menuBarValue(value)
        XCTAssertTrue(spoken.contains("62% used, forecast 97%"))
        XCTAssertFalse(spoken.contains("out of date"))
        XCTAssertFalse(text.resetFacts(value)!.contains("No readings"))
    }

    func testLongTitle_TrimsSpaceBeforeEllipsis() {
        XCTAssertEqual(strings(.english).titleName("Contract work account"), "Contract work…")
    }
}

extension LocalizationTests {
    func testRiskTextColors_UseSystemSemanticColors() {
        XCTAssertEqual(RiskTextColor.color(.onTarget), NSColor.labelColor)
        XCTAssertEqual(RiskTextColor.color(.under), NSColor.controlAccentColor)
        XCTAssertEqual(RiskTextColor.color(.over, severity: .red), NSColor.systemRed)
    }
}

extension LocalizationTests {
    func testFiveHourFacts_CombineUsageWithTimeOnlyReset() {
        let value = AccountUsage(id: "work", name: "Work", source: "claude", weeklyUsed: 62,
                                 fiveHourUsed: 18, reset: nil, fiveHourReset: Date(timeIntervalSince1970: 1804200000),
                                 weekForecast: 84, recentForecast: 97, recordedAt: nil, history: [])
        let result = strings(.english).fiveHourFacts(value)
        XCTAssertTrue(result.hasPrefix("18%, resets "))
        XCTAssertFalse(result.contains("Tue"))
        XCTAssertFalse(result.contains("Wed"))
    }

    func testCompactStaleAge_HandlesTwoDigitHoursInItalian() {
        let result = strings(.italian).staleNote(Date().addingTimeInterval(-42 * 3600))
        XCTAssertTrue(result.hasPrefix("vecchia di "))
        XCTAssertLessThan(result.count, 32)
        XCTAssertFalse(result.contains(" fa"))
    }
}

extension LocalizationTests {
    func testRefreshFailure_AnnouncesWhetherLastReadingWasRetained() {
        let text = strings(.english)
        XCTAssertEqual(text.refreshFailure(hasReading: true), "Could not refresh. Leeway kept the last reading.")
        XCTAssertTrue(text.refreshFailure(hasReading: false).hasPrefix("No reading yet."))
    }

    func testStaleAge_UsesSelectedLanguageForUnits() {
        let text = strings(.italian)
        let now = Date(timeIntervalSince1970: 1804200000)
        let result = text.staleNote(now.addingTimeInterval(-42 * 3600), relativeTo: now)
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "it")
        formatter.calendar = calendar
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        XCTAssertEqual(result, "vecchia di " + formatter.string(from: 42 * 3600)!)
    }
}

extension LocalizationTests {
    func testReset_StaleReadingKeepsResetAndSeparateAccessibleAge() {
        let text = strings(.english)
        let now = Date(timeIntervalSince1970: 1804200000)
        var value = AccountUsage(id: "work", name: "Work", source: "Claude", weeklyUsed: 62,
            fiveHourUsed: nil, reset: now.addingTimeInterval(86400), fiveHourReset: nil,
            weekForecast: 84, recentForecast: 97, recordedAt: now.addingTimeInterval(-1801), history: [])
        value.isStale = true
        XCTAssertTrue(text.resetFacts(value)!.hasPrefix("Resets "))
        XCTAssertNotNil(text.readingAge(value, pollingMinutes: 15, now: now))
        XCTAssertTrue(text.readingAgeLabel(value, pollingMinutes: 15, now: now)!.hasPrefix("Reading is "))
        XCTAssertNil(text.readingAge(value, pollingMinutes: 30, now: now))
    }

    func testAverageOnlyForecast_MenuAndHeadlineUseSingleValue() {
        let value = account(used: 13, week: 16.3, recent: nil)
        XCTAssertEqual(strings(.english).usageFacts(value), "13% now, 16% at reset, target 75-100%")
        XCTAssertEqual(strings(.italian).usageFacts(value), "13% ora, 16% al reset, target 75-100%")
        XCTAssertEqual(strings(.english).menuBarTitle(value), "Work 13% → 16%")
        XCTAssertTrue(strings(.english).headline(value).hasPrefix("Lands at 16%"))
        XCTAssertFalse(strings(.english).headline(value).contains("between"))
    }
}

extension LocalizationTests {
    func testAdvisorReason_UsesSameForecastAndStatusAsMenu() {
        let forecast = LeewayCore.Forecast(averagePctAtReset: 116.5, recentPctAtReset: 95,
            rangeLow: 95, rangeHigh: 116.5, nextRoundPct: 96, exhaustsAt: nil, confidence: .medium)
        let status = LeewayCore.AccountStatus(id: "work", label: "Work", provider: .claude, configDir: "/fixture",
            sevenDay: LeewayCore.UsageWindow(pct: 95, resetsAt: Date().addingTimeInterval(86400)),
            forecast: forecast, stale: false, targetLow: 65, targetHigh: 75)
        let document = LeewayCore.StatusDocument(generatedAt: Date(), accounts: [status])
        let value = AppCore.CoreSnapshotMapper.map(document)[0]
        let request = LeewayCore.AdviceRequest(repo: "/fixture", role: .builder, taskClass: .integration, agent: .claude)
        let advice = LeewayCore.Advisor.advise(request, document: document, policy: LeewayCore.Policy())
        let displayed = strings(.english).percent(value.upperForecast)
        XCTAssertEqual(displayed, "116%")
        XCTAssertEqual(value.status, .over)
        XCTAssertTrue(strings(.english).menuBarTitle(value).hasSuffix(displayed))
        XCTAssertTrue(advice.reason.contains("forecast at " + displayed))
        XCTAssertFalse(advice.reason.contains("96%"))
        XCTAssertEqual(advice.verdict, .wait)
    }
}

extension LocalizationTests {
    func testForecastRounding_RangeCollapseUsesDisplayedPercentages() {
        let text = strings(.english)
        let distinct = account(used: 95, week: 116.5, recent: 116.6)
        XCTAssertEqual(text.usageFacts(distinct), "95% now, 116-117% at reset, target 75-100%")
        XCTAssertTrue(text.headline(distinct).hasPrefix("Lands between 116% and 117%"))
        let equal = account(used: 95, week: 115.5, recent: 116.5)
        XCTAssertEqual(text.usageFacts(equal), "95% now, 116% at reset, target 75-100%")
        XCTAssertTrue(text.headline(equal).hasPrefix("Lands at 116%"))
    }
}

extension LocalizationTests {
    func testTargetVerdict_UsesOwnerWordsInEnglishAndItalian() {
        let under = account(week: 65, recent: 70)
        let onTarget = account(week: 70, recent: 84)
        let over = account(week: 101, recent: 120)
        XCTAssertEqual(strings(.english).status(under), "Room to use")
        XCTAssertEqual(strings(.italian).status(under), "Quota da usare")
        XCTAssertEqual(strings(.english).status(onTarget), "On target")
        XCTAssertEqual(strings(.italian).status(onTarget), "Nell'intervallo")
        XCTAssertEqual(strings(.english).status(over), "Over target")
        XCTAssertEqual(strings(.italian).status(over), "Sopra l'intervallo")
        XCTAssertEqual(strings(.english).usageFacts(onTarget), "62% now, 70-84% at reset, target 75-100%")
        XCTAssertEqual(RiskTextColor.color(.over, severity: .amber), .systemOrange)
    }
}

extension LocalizationTests {
    func testDetailFacts_AverageOnlyHidesUnknownFiveHourAndRecentValues() {
        let facts = strings(.english).detailFacts(account(used: 13, week: 16.3, recent: nil))
        XCTAssertEqual(facts.map(\.label), ["Weekly used", "Forecast, week pace", "Target"])
        XCTAssertEqual(facts.map(\.value), ["13%", "16%", "75-100%"])
    }

    func testDetailFacts_UnknownReadingShowsOnlyTarget() {
        let facts = strings(.english).detailFacts(account(used: nil, week: nil, recent: nil))
        XCTAssertEqual(facts.map(\.label), ["Target"])
        XCTAssertEqual(facts.map(\.value), ["75-100%"])
    }
}

extension LocalizationTests {
    func testMenuCaption_ListsUsageForecastAndResetInPlainWords() {
        let value = account(used: 96, week: 102, recent: 116)
        let english = strings(.english)
        let reset = english.date(value.reset)
        XCTAssertEqual(english.menuCaption(value), "96% used, forecast 102-116%, target 75-100%, resets \(reset)")
        XCTAssertEqual(strings(.italian).menuCaption(value),
                       "96% usato, previsione 102-116%, target 75-100%, reset \(strings(.italian).date(value.reset))")
    }

    func testMenuCaption_MissingForecastOrReset_SaysSoInsteadOfHidingIt() {
        let text = strings(.english)
        XCTAssertEqual(text.menuCaption(account(week: nil, reset: nil)),
                       "62% used, forecast unavailable, target 75-100%, reset time unknown")
        XCTAssertEqual(text.menuCaption(account(used: 13, week: 16.3, recent: nil, reset: nil)),
                       "13% used, forecast 16%, target 75-100%, reset time unknown")
    }

    func testMenuCaption_NoReading_ExplainsWhy() {
        let text = strings(.english)
        XCTAssertEqual(text.menuCaption(account(used: nil)), text.usageFacts(account(used: nil)))
    }

    func testMenuCaption_ContainsNoMiddleDotsOrEmDashes() {
        for language in [AppLanguage.english, .italian] {
            let caption = strings(language).menuCaption(account())
            XCTAssertFalse(caption.contains("·") || caption.contains("\u{2014}"))
        }
    }
}

extension LocalizationTests {
    func testForecastHeadline_RangeIsTheNumberAndResetIsTheCaption() throws {
        let value = account(used: 96, week: 102, recent: 116)
        let english = try XCTUnwrap(strings(.english).forecastHeadline(value))
        XCTAssertEqual(english.value, "102-116%")
        XCTAssertEqual(english.caption, "at reset \(strings(.english).date(value.reset))")
        XCTAssertEqual(try XCTUnwrap(strings(.italian).forecastHeadline(value)).caption,
                       "al reset \(strings(.italian).date(value.reset))")
    }

    func testForecastHeadline_PointForecast_ShowsOneNumber() throws {
        let value = account(used: 13, week: 16.3, recent: nil)
        XCTAssertEqual(try XCTUnwrap(strings(.english).forecastHeadline(value)).value, "16%")
    }

    func testForecastHeadline_NoForecast_FallsBackToUsage() throws {
        let headline = try XCTUnwrap(strings(.english).forecastHeadline(account(week: nil)))
        XCTAssertEqual(headline.value, "62%")
        XCTAssertEqual(headline.caption, "used so far")
    }

    func testForecastHeadline_NoReading_IsNil() {
        XCTAssertNil(strings(.english).forecastHeadline(account(used: nil)))
    }
}

extension LocalizationTests {
    func testKnownUsageWithoutForecast_HasNeutralUnavailableVerdict() {
        let value = account(week: nil, recent: nil)
        XCTAssertEqual(strings(.english).status(value), "Forecast unavailable")
        XCTAssertEqual(strings(.italian).status(value), "Previsione non disponibile")
    }
}

extension LocalizationTests {
    func testPendingReading_ShowsProgressThenTheTypedFailure() {
        var value = account(used: nil)
        value.error = .timeout
        let text = strings(.english)
        XCTAssertEqual(text.status(value, isRefreshing: true), "Reading")
        XCTAssertEqual(text.menuCaption(value, isRefreshing: true), "Reading usage")
        XCTAssertEqual(text.status(value), "No reading")
        XCTAssertEqual(text.menuCaption(value), "Reading timed out")
    }
}


extension LocalizationTests {
    func testForecastSentence_LocalizesWeekdayAndRange() throws {
        let reset = try XCTUnwrap(Calendar(identifier: .gregorian).date(from:
            DateComponents(year: 2026, month: 11, day: 7, hour: 12)))
        let value = account(used: 27, week: 55, recent: 69, reset: reset)
        XCTAssertEqual(try XCTUnwrap(strings(.english).forecastSentence(value)),
                       "At the Saturday reset, you reach 55-69%")
        XCTAssertEqual(try XCTUnwrap(strings(.italian).forecastSentence(value)),
                       "Al reset di sabato arrivi al 55-69%")
    }

    func testForecastSentence_UsesExplicitFallbacksWithoutForecastOrReset() {
        XCTAssertEqual(strings(.english).forecastSentence(account(reset: nil)), "At reset you reach 84-97%")
        XCTAssertEqual(strings(.italian).forecastSentence(account(reset: nil)), "Al reset arrivi al 84-97%")
        XCTAssertNil(strings(.english).forecastSentence(account(week: nil)))
        XCTAssertNil(strings(.english).forecastSentence(account(used: nil)))
    }
}
