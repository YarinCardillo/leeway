import SwiftUI

/// Temporary native title studies, pending the owner's choice.
enum DetailHeaderVariant: String {
    case standard
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
}

struct DetailForecastValue: View {
    let value: String
    let variant: DetailHeaderVariant

    var body: some View {
        switch variant {
        case .standard:
            Text(value).font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
        case .a:
            styled(size: 34, weight: .light, width: .standard, percentSize: 18)
        case .b:
            styled(size: 32, weight: .regular, width: .expanded, percentSize: 17)
        case .c:
            styled(size: 40, weight: .semibold, width: .compressed, percentSize: 20)
        case .d:
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
        }
    }

    private func styled(size: CGFloat, weight: Font.Weight, width: Font.Width, percentSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
                .font(.system(size: size, weight: weight).width(width))
            if value.contains("%") {
                Text("%").font(.system(size: percentSize, weight: .regular).width(width)).foregroundStyle(.secondary)
            }
        }.monospacedDigit()
    }
}
