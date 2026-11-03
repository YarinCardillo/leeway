import AppKit
import AppModel

/// Preference-style toolbar tabs, the way System Settings and native Settings windows choose a pane.
@MainActor
final class SettingsToolbar: NSObject, NSToolbarDelegate {
    private let navigation: SettingsNavigation
    private let model: UsageModel
    private let toolbar = NSToolbar(identifier: "LeewaySettingsToolbar")
    private weak var window: NSWindow?
    private var strings: Localizer { Localizer(language: model.preferences.language) }

    init(navigation: SettingsNavigation, model: UsageModel) {
        self.navigation = navigation
        self.model = model
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = Self.identifier(navigation.tab)
    }

    func install(in window: NSWindow) {
        self.window = window
        window.toolbarStyle = .preference
        window.toolbar = toolbar
        refreshLabels()
    }

    /// Labels follow the app language, and the window is titled with the selected pane like System Settings.
    func refreshLabels() {
        for item in toolbar.items {
            guard let tab = SettingsTab(rawValue: item.itemIdentifier.rawValue) else { continue }
            item.label = strings.text(tab.titleKey)
        }
        window?.title = strings.text(navigation.tab.titleKey)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.identifiers }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.identifiers }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.identifiers }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = strings.text(tab.titleKey)
        item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: nil)
        item.target = self
        item.action = #selector(select(_:))
        return item
    }

    @objc private func select(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        navigation.tab = tab
        toolbar.selectedItemIdentifier = Self.identifier(tab)
        refreshLabels()
    }

    private static let identifiers = SettingsTab.allCases.map { identifier($0) }

    nonisolated private static func identifier(_ tab: SettingsTab) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(tab.rawValue)
    }
}
