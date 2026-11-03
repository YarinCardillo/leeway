import AppModel
import SwiftUI

struct AccountDetail: View {
    let account: AccountUsage
    let model: UsageModel
    let strings: Localizer
    let selection: ChartSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let account = model.accounts.first { $0.id == self.account.id } ?? self.account
        return VStack(alignment: .leading, spacing: 8) {
            header(account)
            if account.weeklyUsed != nil, account.reset != nil {
                WeeklyChart(account: account, strings: strings, selection: selection).frame(height: 170)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                ForEach(strings.detailFacts(account), id: \.label) { fact in
                    factRow(fact.label, fact.value)
                }
            }.font(.subheadline)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14).padding(.vertical, 10).frame(width: 340)
    }

    private func header(_ account: AccountUsage) -> some View {
        let age = strings.readingAge(account, pollingMinutes: model.preferences.pollingMinutes)
        return VStack(alignment: .leading, spacing: 2) {
            Text(account.name).font(.subheadline).foregroundStyle(.secondary)
            if let forecast = strings.forecastHeadline(account) {
                forecastTitle(forecast.value, account: account)
                Text(selection.date.flatMap { account.chartReadout(at: $0) }.map(strings.chartReadout) ?? forecast.caption)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(2).frame(height: 28, alignment: .topLeading)
            } else {
                Text(strings.usageFacts(account)).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if let error = strings.detailReadError(account) {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
            }
            if let age { Text(age).font(.subheadline).foregroundStyle(.orange) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(strings.headline(account, pollingMinutes: model.preferences.pollingMinutes))
    }

    private func forecastTitle(_ value: String, account: AccountUsage) -> some View {
        HStack(alignment: .firstTextBaseline) {
            DetailForecastValue(value: value)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: value)
            Spacer(minLength: 8)
            Text(strings.status(account)).font(.subheadline.weight(.semibold)).foregroundStyle(account.verdictTint)
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).fixedSize(horizontal: false, vertical: true)
            Text(value).monospacedDigit().foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
        }.accessibilityElement(children: .combine)
    }
}
