import AppModel
import SwiftUI

struct UpdatesSettings: View {
    let model: UsageModel
    let updates: UpdateController
    let strings: Localizer

    var body: some View {
        Form {
            Section {
                Toggle(strings.text("Check for updates automatically"), isOn: Binding(
                    get: { model.preferences.updatesAutomatically }, set: { model.setAutomaticUpdates($0) }
                ))
                LabeledContent(strings.text("Current version")) {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? strings.text("Unavailable"))
                        .monospacedDigit()
                }
                LabeledContent(strings.text("Updates")) {
                    Button(strings.text("Check Now"), action: updates.checkNow)
                        .disabled(updates.isConfigured && !updates.canCheck)
                }
            } footer: {
                if !updates.isConfigured || updates.checkResult == .notConfigured {
                    Text(strings.text("Updates are not set up in this build."))
                }
            }
        }.formStyle(.grouped)
    }
}
