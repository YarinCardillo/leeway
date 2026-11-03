import AppModel
import SwiftUI
import UniformTypeIdentifiers

struct AccountsSettings: View {
    let model: UsageModel
    let strings: Localizer
    @State private var isChoosingFolder = false
    @State private var pendingFolder: URL?

    var body: some View {
        Form {
            ForEach(model.accounts) { account in accountSettings(account) }
            if model.accounts.isEmpty { Text(strings.text("No accounts found")) }
            Section {
                ForEach(model.preferences.addedFolders, id: \.self) { folder in
                    HStack {
                        Text(folder).font(.subheadline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(strings.text("Remove")) { model.removeFolder(folder); Task { await model.refresh() } }
                            .accessibilityLabel(strings.format("Remove %@", folder))
                    }
                }
                Button(strings.text("Add Folder…")) { isChoosingFolder = true }
            }
        }.formStyle(.grouped)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                pendingFolder = url
            }
        }
        .confirmationDialog(strings.text("Which app does this folder belong to?"), isPresented: Binding(
            get: { pendingFolder != nil }, set: { if !$0 { pendingFolder = nil } }
        )) {
            Button("Claude Code") { addFolder(provider: "claude") }
            Button("Codex") { addFolder(provider: "codex") }
        }
    }

    private func addFolder(provider: String) {
        guard let folder = pendingFolder else { return }
        model.addFolder(folder.path, provider: provider)
        pendingFolder = nil
        Task { await model.refresh() }
    }

    private func accountSettings(_ account: AccountUsage) -> some View {
        Section {
            AccountNameField(account: account, model: model, strings: strings)
            Toggle(strings.text("Show in menu"), isOn: Binding(
                get: { account.isEnabled }, set: { model.setEnabled($0, for: account.id) }
            )).accessibilityLabel(strings.format("Enabled for %@", account.name))
            LabeledContent {
                HStack(spacing: 12) {
                    Text(strings.targetRange(account)).monospacedDigit().foregroundStyle(.secondary)
                    TargetRangeControl(low: account.targetLow, high: account.targetHigh, strings: strings) { low, high in
                        model.setTarget(low: low, high: high, for: account.id)
                    }
                    .frame(width: 150)
                }
            } label: {
                Text(strings.text("Target"))
                Text(strings.text("Your weekly usage at reset"))
            }
            reservePicker(account)
        } header: {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                Text(abbreviated(account.folder.isEmpty ? account.source : account.folder))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func reservePicker(_ account: AccountUsage) -> some View {
        Picker(strings.text("Reserve account"), selection: Binding(
            get: { model.preferences.accounts[account.id]?.reserveID ?? "" },
            set: { model.setReserve($0.isEmpty ? nil : $0, for: account.id) }
        )) {
            Text(strings.text("None")).tag("")
            ForEach(model.accounts.filter { $0.id != account.id }) { Text($0.name).tag($0.id) }
        }.pickerStyle(.menu).accessibilityLabel(strings.format("Reserve account for %@", account.name))
    }

}
