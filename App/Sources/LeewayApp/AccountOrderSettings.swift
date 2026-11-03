import AppModel
import SwiftUI

/// Native List supplies drag reordering; the model owns and persists the resulting order.
struct AccountOrderSettings: View {
    let model: UsageModel
    let strings: Localizer
    @State private var selection = Set<String>()

    var body: some View {
        Section {
            orderPicker
            accountList
            if model.preferences.accountOrderMode == .manual {
                Text(strings.text("Drag accounts to change their order."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var orderPicker: some View {
        Picker(strings.text("Account order"), selection: Binding(
            get: { model.preferences.accountOrderMode }, set: { model.setAccountOrderMode($0) }
        )) {
            Text(strings.text("Manual")).tag(AccountOrderMode.manual)
            Text(strings.text("Most at risk first")).tag(AccountOrderMode.mostAtRisk)
        }
    }

    private var accountList: some View {
        List(selection: $selection) {
            ForEach(model.orderedAccounts) { account in
                Text(account.name).tag(account.id).moveDisabled(model.preferences.accountOrderMode != .manual)
            }
            .onMove { model.moveAccounts(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.inset)
        .frame(height: min(180, max(60, CGFloat(model.accounts.count) * 28 + 8)))
        .accessibilityLabel(strings.text("Account order"))
    }
}
