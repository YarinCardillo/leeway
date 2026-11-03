import AppModel
import SwiftUI

/// Owner-requested two-handle exception to native-only controls, using the system slider appearance.
struct TargetRangeControl: View {
    let low: Double
    let high: Double
    let strings: Localizer
    let onChange: (Double, Double) -> Void
    @FocusState private var focusedHandle: TargetRangeAdjustment.Handle?
    @State private var keyboardHandle: TargetRangeAdjustment.Handle?
    @State private var draggedHandle: TargetRangeAdjustment.Handle?
    private let thumbSize: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - thumbSize, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 4).padding(.horizontal, thumbSize / 2)
                Capsule().fill(Color.accentColor)
                    .frame(width: width * (high - low) / 100, height: 4)
                    .offset(x: thumbSize / 2 + width * low / 100)
                handle(.low, width: width)
                handle(.high, width: width)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                keyboardHandle = nil
                let start = (gesture.startLocation.x - thumbSize / 2) / width * 100
                let handle = draggedHandle ?? TargetRangeAdjustment.nearest(to: start, low: low, high: high)
                draggedHandle = handle
                set(TargetRangeAdjustment.value((gesture.location.x - thumbSize / 2) / width * 100,
                    for: handle, low: low, high: high), handle: handle)
            }.onEnded { _ in draggedHandle = nil })
        }
        .frame(height: 24)
        .accessibilityElement(children: .contain)
        .onChange(of: focusedHandle) { _, handle in
            keyboardHandle = NSApp.currentEvent?.type == .keyDown ? handle : nil
        }
    }

    private func handle(_ handle: TargetRangeAdjustment.Handle, width: CGFloat) -> some View {
        let value = handle == .low ? low : high
        return Circle().fill(Color.white)
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.25), radius: 1, y: 1)
            .overlay {
                if keyboardHandle == handle {
                    Circle().stroke(Color.accentColor, lineWidth: 1).padding(-2)
                }
            }
            .frame(width: thumbSize, height: thumbSize)
            .frame(width: 24, height: 24).contentShape(Rectangle())
            .focusable().focused($focusedHandle, equals: handle).focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                keyboardHandle = handle
                move(handle, increasing: press.key == .rightArrow || press.key == .upArrow)
                return .handled
            }
            .accessibilityLabel(strings.text(handle == .low ? "Target low" : "Target high"))
            .accessibilityValue(strings.percent(value))
            .accessibilityAdjustableAction { direction in
                if direction == .increment { move(handle, increasing: true) }
                else if direction == .decrement { move(handle, increasing: false) }
            }
            .offset(x: width * value / 100 - (24 - thumbSize) / 2)
    }

    private func move(_ handle: TargetRangeAdjustment.Handle, increasing: Bool) {
        set(TargetRangeAdjustment.move(handle, increasing: increasing, low: low, high: high), handle: handle)
    }

    private func set(_ value: Double, handle: TargetRangeAdjustment.Handle) {
        onChange(handle == .low ? value : low, handle == .high ? value : high)
    }
}
