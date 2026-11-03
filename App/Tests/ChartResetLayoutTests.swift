import AppKit
import AppModel
import Charts
import SwiftUI
import XCTest
@testable import LeewayPresentation

@MainActor
final class ChartResetLayoutTests: XCTestCase {
    func testChart_ResetIsTheRightDataEdgeWithYAxisLabelsOutside() throws {
        let account = TestProvider.readings[0]
        let reset = try XCTUnwrap(account.reset)
        let start = reset.addingTimeInterval(-7 * 86400)
        let probe = ResetPlotProbe(start: start, reset: reset)
        let chart = WeeklyChart(account: account, strings: Localizer(language: .english), selection: ChartSelection())
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let _ = probe.capture(proxy: proxy, geometry: geometry)
                    Color.clear
                }
            }
            .frame(width: 310, height: 170)
        XCTAssertNotNil(ImageRenderer(content: chart).cgImage)
        let width = try XCTUnwrap(probe.width)
        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThan(width, 310)
        XCTAssertEqual(try XCTUnwrap(probe.startX), 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(probe.resetX), width, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(probe.edgeDate).timeIntervalSince(reset), 0, accuracy: 0.001)
    }
}

@MainActor
private final class ResetPlotProbe {
    let start: Date
    let reset: Date
    var width: CGFloat?
    var startX: CGFloat?
    var resetX: CGFloat?
    var edgeDate: Date?

    init(start: Date, reset: Date) { self.start = start; self.reset = reset }

    func capture(proxy: ChartProxy, geometry: GeometryProxy) {
        guard let frame = proxy.plotFrame else { return }
        let width = geometry[frame].width
        self.width = width
        startX = proxy.position(forX: start)
        resetX = proxy.position(forX: reset)
        edgeDate = proxy.value(atX: width, as: Date.self)
    }
}
