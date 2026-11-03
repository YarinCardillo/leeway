import AppModel
import Foundation
import LeewayCore
import SwiftUI

struct Localizer {
    let language: AppLanguage
    let resourceBundle: Bundle?

    init(language: AppLanguage, resourceBundle: Bundle? = nil) {
        self.language = language
        self.resourceBundle = resourceBundle
    }

    var locale: Locale { language.locale }
    private var bundle: Bundle {
        if let resourceBundle { return resourceBundle }
        let code: String
        switch language {
        case .english: code = "en"
        case .italian: code = "it"
        case .system: code = Locale.preferredLanguages.first?.hasPrefix("it") == true ? "it" : "en"
        }
        return Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    func text(_ key: String) -> String { bundle.localizedString(forKey: key, value: key, table: nil) }
    func format(_ key: String, _ values: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: values)
    }
    func percent(_ value: Double?) -> String {
        guard let value else { return text("Unavailable") }
        return (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
    func date(_ value: Date?) -> String {
        guard let value else { return text("Unavailable") }
        return value.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(locale))
    }
    func age(_ value: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        return formatter.localizedString(for: value, relativeTo: Date())
    }
    func status(_ account: AccountUsage, isRefreshing: Bool = false) -> String {
        guard account.weeklyUsed != nil else { return text(isRefreshing ? "Reading" : "No reading") }
        guard account.lowerForecast != nil, account.upperForecast != nil else { return text("Forecast unavailable") }
        switch account.status {
        case .onTarget: return text("On target")
        case .under: return text("Room to use")
        case .over: return text("Over target")
        }
    }
}

extension Localizer {
    func period(endingAt reset: Date) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: reset.addingTimeInterval(-7 * 86400), to: reset)
    }

    func chartReadout(_ point: ChartReadout) -> String {
        let time = point.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute().locale(locale))
        return point.isForecast ? format("%@, forecast %@ to %@", time, percent(point.lower), percent(point.upper))
            : format("%@, %@ used", time, percent(point.lower))
    }

    func refreshFailure(hasReading: Bool) -> String {
        text(hasReading ? "Could not refresh. Leeway kept the last reading."
             : "No reading yet. Check that Claude Code or Codex is signed in, then choose Refresh Now.")
    }

    func updated(_ date: Date?, isRefreshing: Bool) -> String? {
        if isRefreshing { return text("Updating") }
        return date.map { format("Updated %@", age($0)) }
    }

    func readError(_ account: AccountUsage) -> String? {
        account.error.map { text("read_error." + $0.rawValue) }
    }

    func detailReadError(_ account: AccountUsage) -> String? {
        account.weeklyUsed == nil ? nil : readError(account)
    }

    func usageFacts(_ account: AccountUsage) -> String {
        guard let used = account.weeklyUsed else {
            return readError(account) ?? text("No reading yet. Check that Claude Code or Codex is signed in, then choose Refresh Now.")
        }
        let target = targetRange(account)
        guard let low = account.lowerForecast, let high = account.upperForecast else {
            return format("%@ now, forecast unavailable, target %@", percent(used), target)
        }
        let forecast = percent(low) == percent(high) ? percent(high) : "\(number(low))-\(percent(high))"
        return format("%@ now, %@ at reset, target %@", percent(used), forecast, target)
    }

    /// The quiet third line of a menu row: what was used, where the forecast lands and when the week resets.
    func menuCaption(_ account: AccountUsage, isRefreshing: Bool = false) -> String {
        if account.weeklyUsed == nil, isRefreshing { return text("Reading usage") }
        guard let used = account.weeklyUsed else { return usageFacts(account) }
        var parts = [format("%@ used", percent(used))]
        if let low = account.lowerForecast, let high = account.upperForecast {
            parts.append(format("forecast %@", percent(low) == percent(high) ? percent(high) : "\(number(low))-\(percent(high))"))
        } else { parts.append(text("forecast unavailable")) }
        parts.append(format("target %@", targetRange(account)))
        parts.append(account.reset.map { format("resets %@", date($0)) } ?? text("reset time unknown"))
        let caption = parts.joined(separator: ", ")
        return readError(account).map { caption + "\n" + $0 } ?? caption
    }

    /// The large number of the detail header and the words under it. Nil without a reading.
    func forecastHeadline(_ account: AccountUsage) -> (value: String, caption: String)? {
        guard let used = account.weeklyUsed else { return nil }
        guard let low = account.lowerForecast, let high = account.upperForecast else {
            return (percent(used), text("used so far"))
        }
        let value = percent(low) == percent(high) ? percent(high) : "\(number(low))-\(percent(high))"
        return (value, account.reset.map { format("at reset %@", date($0)) } ?? text("at reset"))
    }

    func targetRange(_ account: AccountUsage) -> String {
        "\(number(account.targetLow))-\(percent(account.targetHigh))"
    }

    func detailFacts(_ account: AccountUsage) -> [(label: String, value: String)] {
        var facts: [(String, String)] = []
        if let used = account.weeklyUsed { facts.append((text("Weekly used"), percent(used))) }
        if account.fiveHourUsed != nil { facts.append((text("Five-hour used"), fiveHourFacts(account))) }
        if let week = account.weekForecast { facts.append((text("Forecast, week pace"), percent(week))) }
        if let recent = account.recentForecast { facts.append((text("Forecast, last 24 hours"), percent(recent))) }
        facts.append((text("Target"), targetRange(account)))
        return facts
    }

    func fiveHourFacts(_ account: AccountUsage) -> String {
        guard let used = account.fiveHourUsed else { return text("Unavailable") }
        guard let reset = account.fiveHourReset else { return percent(used) }
        let time = reset.formatted(.dateTime.hour().minute().locale(locale))
        return format("%@, resets %@", percent(used), time)
    }

    func resetFacts(_ account: AccountUsage) -> String? {
        guard account.weeklyUsed != nil else { return nil }
        return account.reset.map { format("Resets %@", date($0)) } ?? text("Reset time unknown")
    }

    func readingAge(_ account: AccountUsage, pollingMinutes: Int, now: Date = Date()) -> String? {
        guard account.isReadingOld(pollingMinutes: pollingMinutes, now: now) else { return nil }
        return staleNote(account.recordedAt, relativeTo: now)
    }

    func readingAgeLabel(_ account: AccountUsage, pollingMinutes: Int, now: Date = Date()) -> String? {
        readingAge(account, pollingMinutes: pollingMinutes, now: now).map { format("Reading is %@", $0) }
    }

    func staleNote(_ date: Date?, relativeTo now: Date = Date()) -> String {
        guard let date else { return text("Last reading is out of date") }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        let duration = formatter.string(from: max(60, now.timeIntervalSince(date))) ?? ""
        return format("%@ old", duration)
    }

    func headline(_ account: AccountUsage, pollingMinutes: Int = 15, now: Date = Date()) -> String {
        let forecast: String
        if account.weeklyUsed == nil { return usageFacts(account) }
        if let low = account.lowerForecast, let high = account.upperForecast {
            if percent(low) == percent(high) {
                forecast = account.reset.map { format("Lands at %@ on %@", percent(high), date($0)) }
                    ?? format("Lands at %@", percent(high))
            } else {
                forecast = account.reset.map { format("Lands between %@ and %@ on %@", percent(low), percent(high), date($0)) }
                    ?? format("Forecast between %@ and %@", percent(low), percent(high))
            }
        } else { forecast = text("Forecast not available yet") }
        return readingAge(account, pollingMinutes: pollingMinutes, now: now).map { "\($0). \(forecast)" } ?? forecast
    }

    func menuBarTitle(_ account: AccountUsage) -> String {
        let title = "\(titleName(account.name)) \(percent(account.weeklyUsed))"
        return account.upperForecast.map { title + " → " + percent($0) } ?? title
    }

    func menuBarValue(_ account: AccountUsage, pollingMinutes: Int = 15, now: Date = Date()) -> String {
        let value = account.upperForecast.map {
            format("%@, %@ used, forecast %@, %@", account.name, percent(account.weeklyUsed), percent($0), status(account))
        } ?? format("%@, %@ used, %@", account.name, percent(account.weeklyUsed), status(account))
        return readingAgeLabel(account, pollingMinutes: pollingMinutes, now: now).map { "\(value), \($0)" } ?? value
    }

    func titleName(_ name: String) -> String {
        let maximumLength = 14
        return name.count > maximumLength
            ? String(name.prefix(maximumLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…" : name
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }
}

enum RiskTextColor {
    static func verdict(_ account: AccountUsage) -> NSColor {
        guard account.weeklyUsed != nil, account.lowerForecast != nil, account.upperForecast != nil else {
            return .secondaryLabelColor
        }
        return verdict(account.status, severity: account.severity)
    }

    /// The verdict word and the forecast mark: the accent for room to use, a quiet secondary on target.
    static func verdict(_ status: UsageStatus, severity: RiskSeverity? = nil) -> NSColor {
        status == .onTarget ? .secondaryLabelColor : color(status, severity: severity)
    }

    static func color(_ status: UsageStatus, severity: RiskSeverity? = nil) -> NSColor {
        switch status {
        case .onTarget: .labelColor
        case .under: .controlAccentColor
        case .over: severity == .red ? .systemRed : .systemOrange
        }
    }
}

extension AccountUsage {
    var chartTint: Color { Color(nsColor: RiskTextColor.color(status, severity: severity)) }
    var verdictTint: Color { Color(nsColor: RiskTextColor.verdict(self)) }
}
