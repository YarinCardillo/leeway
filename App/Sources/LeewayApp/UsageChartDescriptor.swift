import Accessibility
import AppModel
import SwiftUI

struct UsageChartDescriptor: AXChartDescriptorRepresentable {
    let account: AccountUsage
    let strings: Localizer

    func makeChartDescriptor() -> AXChartDescriptor {
        let reset = account.reset ?? Date()
        let start = reset.addingTimeInterval(-7 * 86400)
        let xAxis = AXNumericDataAxisDescriptor(title: strings.text("Date"),
            range: start.timeIntervalSince1970...reset.timeIntervalSince1970, gridlinePositions: []) {
                strings.date(Date(timeIntervalSince1970: $0))
            }
        let yAxis = AXNumericDataAxisDescriptor(title: strings.text("Weekly used"), range: account.chartYDomain,
                                               gridlinePositions: [0, 50, 100]) { strings.percent($0) }
        return AXChartDescriptor(title: strings.format("Weekly usage for %@", account.name),
                                 summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: series(reset: reset))
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let current = makeChartDescriptor()
        descriptor.title = current.title
        descriptor.xAxis = current.xAxis
        descriptor.yAxis = current.yAxis
        descriptor.series = current.series
    }

    private func series(reset: Date) -> [AXDataSeriesDescriptor] {
        let startDate = reset.addingTimeInterval(-7 * 86400)
        let measured = account.chartSeries(from: startDate, to: reset)
        var result = [makeSeries("Weekly used", points: measured.line)]
        if let current = measured.now {
            if let value = account.weekForecast {
                result.append(makeSeries("Forecast, week pace", points: [current, UsagePoint(date: reset, used: max(current.used, value))]))
            }
            if let value = account.recentForecast {
                result.append(makeSeries("Forecast, last 24 hours", points: [current, UsagePoint(date: reset, used: max(current.used, value))]))
            }
        }
        let start = reset.addingTimeInterval(-7 * 86400)
        for (label, value) in [("Target low", account.targetLow), ("Target high", account.targetHigh)] {
            result.append(makeSeries(label, points: [UsagePoint(date: start, used: value), UsagePoint(date: reset, used: value)]))
        }
        result.append(makeSeries("Limit", points: [UsagePoint(date: start, used: 100), UsagePoint(date: reset, used: 100)]))
        return result
    }

    private func makeSeries(_ name: String, points: [UsagePoint]) -> AXDataSeriesDescriptor {
        AXDataSeriesDescriptor(name: strings.text(name), isContinuous: true, dataPoints: points.map {
            AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.used)
        })
    }
}
