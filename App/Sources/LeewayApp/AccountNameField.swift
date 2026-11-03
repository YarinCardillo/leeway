import AppModel
import SwiftUI

struct AccountNameField: View {
    let account: AccountUsage
    let model: UsageModel
    let strings: Localizer
    @State private var draft: AccountNameDraft
    @FocusState private var hasFocus: Bool

    init(account: AccountUsage, model: UsageModel, strings: Localizer) {
        self.account = account
        self.model = model
        self.strings = strings
        _draft = State(initialValue: AccountNameDraft(account.name))
    }

    var body: some View {
        TextField(strings.text("Name"), text: Binding(get: { draft.text }, set: { draft.update($0) }),
                  prompt: Text(strings.text("Account name")))
            .focused($hasFocus)
            .accessibilityLabel(strings.text("Account name")).accessibilityHint(account.folder)
            .onSubmit { commit(); hasFocus = false }
            .onExitCommand {
                _ = draft.finishEditing(commit: false)
                hasFocus = false
            }
            .onChange(of: hasFocus) { _, isFocused in
                if !isFocused { commit() }
            }
            .onChange(of: account.name) { _, name in if !hasFocus { draft = AccountNameDraft(name) } }
            .onDisappear(perform: commit)
    }

    private func commit() {
        if let name = draft.finishEditing(commit: true), name != account.name { model.rename(name, for: account.id) }
        draft = AccountNameDraft(model.accounts.first { $0.id == account.id }?.name ?? account.name)
    }
}
