import AppModel
import SwiftUI

struct SettingsView: View {
    let model: UsageModel
    let updates: UpdateController
    let navigation: SettingsNavigation
    @State private var contentWidth = 560.0
    @State private var login = LoginController()
    private var strings: Localizer { Localizer(language: model.preferences.language) }

    var body: some View {
        VStack(spacing: 0) {
            pane
            if let error = model.settingsError {
                Label(strings.text(error), systemImage: "exclamationmark.triangle")
                    .font(.callout).fixedSize(horizontal: false, vertical: true).padding()
            }
        }
        .frame(minWidth: SettingsLayout.minimumWidth, idealWidth: contentWidth, minHeight: SettingsLayout.minimumHeight, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .environment(\.locale, strings.locale)
        .onAppear(perform: login.reload)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in login.reload() }
        .onChange(of: model.preferences.updatesAutomatically) { _, _ in updates.configure(model.preferences) }
        .onChange(of: model.settingsError, initial: true) { _, error in
            if let error { AccessibilityNotification.Announcement(strings.text(error)).post() }
        }
        .onChange(of: login.hasError) { _, hasError in
            if hasError {
                AccessibilityNotification.Announcement(strings.text("Could not change login settings. Try again in System Settings.")).post()
            }
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch navigation.tab {
        case .accounts: AccountsSettings(model: model, strings: strings)
        case .general: GeneralSettings(model: model, login: login, strings: strings)
        case .updates: UpdatesSettings(model: model, updates: updates, strings: strings)
        }
    }
}
