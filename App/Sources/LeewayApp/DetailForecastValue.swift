import SwiftUI

struct DetailForecastValue: View {
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
                .font(.system(size: 34, weight: .light))
            if value.contains("%") {
                Text("%").font(.system(size: 18, weight: .regular)).foregroundStyle(.secondary)
            }
        }.monospacedDigit()
    }
}
