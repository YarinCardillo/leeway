import Foundation

/// Discrete range-control movement shared by pointer, keyboard and accessibility input.
public enum TargetRangeAdjustment {
    public enum Handle: Hashable, Sendable { case low, high }
    public static let step = 5.0

    /// Snaps a pointer position to a five-point value while preserving the minimum gap.
    public static func value(_ proposed: Double, for handle: Handle, low: Double, high: Double) -> Double {
        let snapped = (proposed / step).rounded() * step
        switch handle {
        case .low: return min(max(0, snapped), max(0, floor((high - step) / step) * step))
        case .high: return max(min(100, snapped), min(100, ceil((low + step) / step) * step))
        }
    }

    /// Chooses the closest handle even when the two pointer hit areas overlap.
    public static func nearest(to value: Double, low: Double, high: Double) -> Handle {
        abs(value - low) < abs(value - high) ? .low : .high
    }

    /// Moves a handle to the next grid value, including from a fractional policy bound.
    public static func move(_ handle: Handle, increasing: Bool, low: Double, high: Double) -> Double {
        let current = handle == .low ? low : high
        let proposed = increasing ? (floor(current / step) + 1) * step : (ceil(current / step) - 1) * step
        let adjusted = value(proposed, for: handle, low: low, high: high)
        return increasing ? max(current, adjusted) : min(current, adjusted)
    }
}
