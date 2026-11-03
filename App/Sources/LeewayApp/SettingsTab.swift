import Observation

/// The panes of the settings window, in toolbar order.
enum SettingsTab: String, CaseIterable {
    case accounts, general, updates

    var titleKey: String {
        switch self {
        case .accounts: "Accounts"
        case .general: "General"
        case .updates: "Updates"
        }
    }

    var symbolName: String {
        switch self {
        case .accounts: "person.2"
        case .general: "gearshape"
        case .updates: "arrow.down.circle"
        }
    }
}

/// The selected pane, shared by the native toolbar that chooses it and the view that shows it.
@Observable @MainActor
final class SettingsNavigation {
    var tab = SettingsTab.accounts
}
