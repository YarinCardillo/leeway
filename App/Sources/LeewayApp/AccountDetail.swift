import AppModel
import SwiftUI

struct AccountDetail: View {
    let account: AccountUsage
    let model: UsageModel
    let strings: Localizer
    let selection: ChartSelection
    let insets: DetailInsets
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
        .padding(.leading, insets.leading(isPinned: model.preferences.pinnedID == account.id))
        .padding(.trailing, 14).padding(.vertical, 10).frame(width: 340)
    }

    /// The forecast range is the answer, so it is the large number; the verdict sits opposite it in words.
    private func header(_ account: AccountUsage) -> some View {
        let age = strings.readingAge(account, pollingMinutes: model.preferences.pollingMinutes)
        return VStack(alignment: .leading, spacing: 2) {
            Text(account.name).font(.subheadline).foregroundStyle(.secondary)
            if let forecast = strings.forecastHeadline(account) {
                HStack(alignment: .firstTextBaseline) {
                    Text(forecast.value)
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: forecast.value)
                    Spacer(minLength: 8)
                    Text(strings.status(account)).font(.subheadline.weight(.semibold)).foregroundStyle(account.verdictTint)
                }
                Text(selection.date.flatMap { account.chartReadout(at: $0) }.map(strings.chartReadout) ?? forecast.caption)
                    .font(.caption).foregroundStyle(.secondary)
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

    private func factRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).fixedSize(horizontal: false, vertical: true)
            Text(value).monospacedDigit().foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
        }.accessibilityElement(children: .combine)
    }
}
