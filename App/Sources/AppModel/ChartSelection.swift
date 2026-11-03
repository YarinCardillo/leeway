import Foundation
import Observation

/// One cursor state for pointer, keyboard and accessibility chart inspection.
@Observable @MainActor
public final class ChartSelection {
    public private(set) var date: Date?

    public init() {}

    public func select(_ date: Date?) { self.date = date }

    public func step(forward: Bool, in points: [ChartReadout]) {
        guard !points.isEmpty else { return }
        guard let date else { self.date = forward ? points.first?.date : points.last?.date; return }
        if forward { self.date = points.first { $0.date > date }?.date ?? points.last?.date }
        else { self.date = points.last { $0.date < date }?.date ?? points.first?.date }
    }
}
