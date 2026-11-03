import AppModel
import Charts
import SwiftUI

struct WeeklyChart: View {
    let account: AccountUsage
    let strings: Localizer
    let selection: ChartSelection
    private var readout: ChartReadout? { selection.date.flatMap { account.chartReadout(at: $0) } }
    private var reset: Date { account.reset ?? Date() }
    private var start: Date { reset.addingTimeInterval(-7 * 86400) }
    private var series: ChartSeries { account.chartSeries(from: start, to: reset) }
    private var measured: [UsagePoint] { series.measuredLine }
    private var latest: UsagePoint? { series.now }

    var body: some View {
        plottedChart.chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear.onContinuousHover { phase in updateHover(phase, proxy: proxy, geometry: geometry) }
            }
        }
        .accessibilityLabel(strings.format("Weekly usage for %@", account.name))
        .accessibilityValue(readout.map(strings.chartReadout) ?? strings.usageFacts(account))
        .accessibilityAdjustableAction { direction in
            selection.step(forward: direction == .increment, in: account.chartInspectionPoints)
        }
        .accessibilityChartDescriptor(UsageChartDescriptor(account: account, strings: strings))
    }

    private var plottedChart: some View {
        Chart {
            targetBand
            RuleMark(y: .value("Limit", 100)).foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .lineStyle(StrokeStyle(lineWidth: 1))
            measuredMarks
            if let latest {
                PointMark(x: .value("Date", latest.date), y: .value("Used", latest.used))
                    .symbolSize(28).foregroundStyle(Color.primary)
                projections(from: latest)
            }
            readoutMarks
        }
        .chartXScale(domain: start...reset, range: .plotDimension(startPadding: 4, endPadding: 12))
        .chartYScale(domain: account.chartYDomain)
        .padding(.trailing, 8)
        .chartXAxis { AxisMarks(values: .stride(by: .day)) { value in
            AxisValueLabel { if let date = value.as(Date.self) { Text(date, format: .dateTime.weekday(.narrow)).foregroundStyle(.secondary) } }
        } }
        .chartYAxis { AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
            AxisGridLine().foregroundStyle(Color(nsColor: .separatorColor))
            AxisValueLabel { if let number = value.as(Double.self) { Text(strings.percent(number)).foregroundStyle(.secondary) } }
        } }
        .font(.caption).monospacedDigit()
    }

    /// The target is a zone, so it is shaded behind everything instead of drawn as two lines.
    @ChartContentBuilder
    private var targetBand: some ChartContent {
        RectangleMark(xStart: .value("Start", start), xEnd: .value("End", reset),
                      yStart: .value("Target low", account.targetLow), yEnd: .value("Target high", account.targetHigh))
            .foregroundStyle(Color.accentColor.opacity(0.16))
            .annotation(position: .overlay, alignment: .topLeading, spacing: 3) {
                Text(strings.format("Target %@", strings.targetRange(account)))
                    .font(.caption).foregroundStyle(.secondary).fixedSize().padding(.leading, 4)
            }
    }

    @ChartContentBuilder
    private var measuredMarks: some ChartContent {
        ForEach(measured) { point in
            LineMark(x: .value("Date", point.date), y: .value("Used", point.used), series: .value("Series", "Used"))
                .foregroundStyle(Color.primary).lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }

    @ChartContentBuilder
    private func projections(from point: UsagePoint) -> some ChartContent {
        if let low = account.lowerForecast, let high = account.upperForecast {
            ForEach([point.date, reset], id: \.self) { date in
                AreaMark(x: .value("Date", date), yStart: .value("Low", date == reset ? low : point.used),
                         yEnd: .value("High", date == reset ? high : point.used), series: .value("Series", "Forecast area"))
                    .foregroundStyle(account.chartTint.opacity(0.18))
            }
            projection(from: point, to: account.weekForecast ?? point.used, series: "Week pace")
            if let recent = account.recentForecast {
                projection(from: point, to: recent, series: "Recent pace")
            }
        }
    }

    @ChartContentBuilder
    private func projection(from point: UsagePoint, to value: Double, series: String) -> some ChartContent {
        ForEach([point.date, reset], id: \.self) { date in
            LineMark(x: .value("Date", date), y: .value("Forecast", date == reset ? max(point.used, value) : point.used),
                     series: .value("Series", series))
                .foregroundStyle(account.chartTint).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }

    @ChartContentBuilder
    private var readoutMarks: some ChartContent {
        if let readout {
            RuleMark(x: .value("Date", readout.date)).foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(Array(Set([readout.lower, readout.upper])), id: \.self) { value in
                PointMark(x: .value("Date", readout.date), y: .value("Value", value))
                    .symbolSize(22).foregroundStyle(readout.isForecast ? account.chartTint : Color.primary)
            }
        }
    }

    private func updateHover(_ phase: HoverPhase, proxy: ChartProxy, geometry: GeometryProxy) {
        guard case let .active(location) = phase, let frame = proxy.plotFrame else { selection.select(nil); return }
        let plot = geometry[frame]
        guard plot.contains(location), let date: Date = proxy.value(atX: location.x - plot.origin.x) else {
            selection.select(nil); return
        }
        selection.select(account.chartReadout(at: date)?.date)
    }
}
