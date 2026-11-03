import AppModel
import SwiftUI

struct GeneralSettings: View {
    let model: UsageModel
    let login: LoginController
    let strings: Localizer

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(get: { model.preferences.pollingMinutes }, set: { model.setPollingMinutes($0) })) {
                    ForEach(AppPreferences.pollingChoices, id: \.self) { Text(strings.format("%d minutes", $0)).tag($0) }
                } label: {
                    Text(strings.text("Refresh interval"))
                    Text(strings.text("How often Leeway reads your usage"))
                }
                Picker(strings.text("Menu bar"), selection: Binding(
                    get: { model.preferences.isMenuBarCompact }, set: { model.setMenuBarCompact($0) }
                )) {
                    Text(strings.text("Compact")).tag(true)
                    Text(strings.text("Percentages")).tag(false)
                }
                Picker(strings.text("Language"), selection: Binding(
                    get: { model.preferences.language }, set: { model.setLanguage($0) }
                )) {
                    Text(strings.text("System default")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("Italiano").tag(AppLanguage.italian)
                }
                Toggle(strings.text("Launch at login"), isOn: Binding(get: { login.isEnabled }, set: { login.setEnabled($0) }))
                if login.needsApproval { Button(strings.text("Allow in Login Items…"), action: login.openLoginSettings) }
                if login.hasError {
                    Text(strings.text("Could not change login settings. Try again in System Settings.")).font(.subheadline)
                }
            }
        }.formStyle(.grouped)
    }
}
