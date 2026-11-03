import AppCore
import AppModel
import Observation
import SwiftUI

@main
@MainActor
struct LeewayApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = ApplicationDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var model: UsageModel?
    private var updates: UpdateController?
    private var statusItem: NativeStatusItem?
    private var settingsWindow: NSWindowController?
    private let settingsNavigation = SettingsNavigation()
    private var settingsToolbar: SettingsToolbar?
    private var currentLanguage: AppLanguage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider: any UsageProvider
        if ProcessInfo.processInfo.arguments.contains("--mock") { provider = MockUsageProvider() }
        else {
            do { provider = try CoreUsageProvider.live() }
            catch { provider = UnavailableUsageProvider() }
        }
        let model = UsageModel(provider: provider)
        let updates = UpdateController()
        self.model = model
        self.updates = updates
        statusItem = NativeStatusItem(model: model) { [weak self] in self?.showSettings() }
        observeLanguage()
        model.startPolling()
        updates.start(model.preferences)
    }

    func applicationWillTerminate(_ notification: Notification) { model?.stopPolling() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func observeLanguage() {
        guard let model else { return }
        withObservationTracking {
            if currentLanguage != model.preferences.language {
                currentLanguage = model.preferences.language
                configureApplicationMenu()
                settingsToolbar?.refreshLabels()
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeLanguage() }
        }
    }

    private func configureApplicationMenu() {
        guard let model else { return }
        let strings = Localizer(language: model.preferences.language)
        let main = NSMenu()
        for submenu in [applicationMenu(strings), editMenu(strings), windowMenu(strings)] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        NSApplication.shared.mainMenu = main
    }

    private func applicationMenu(_ strings: Localizer) -> NSMenu {
        let menu = NSMenu(title: "Leeway")
        menu.addItem(NSMenuItem(title: strings.text("About Leeway"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        let settings = NSMenuItem(title: strings.text("Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let services = NSMenuItem(title: strings.text("Services"), action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: strings.text("Services"))
        NSApplication.shared.servicesMenu = services.submenu
        menu.addItem(services)
        menu.addItem(NSMenuItem(title: strings.text("Hide Leeway"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let others = NSMenuItem(title: strings.text("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(others)
        menu.addItem(NSMenuItem(title: strings.text("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: strings.text("Quit Leeway"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func editMenu(_ strings: Localizer) -> NSMenu {
        let menu = NSMenu(title: strings.text("Edit"))
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            let item = NSMenuItem(title: strings.text(title), action: Selector(selector), keyEquivalent: key)
            if title == "Redo" { item.keyEquivalentModifierMask = [.command, .shift] }
            menu.addItem(item)
        }
        return menu
    }

    private func windowMenu(_ strings: Localizer) -> NSMenu {
        let menu = NSMenu(title: strings.text("Window"))
        menu.addItem(NSMenuItem(title: strings.text("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: strings.text("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        NSApplication.shared.windowsMenu = menu
        return menu
    }

    @objc private func showSettings() {
        guard let model, let updates else { return }
        if settingsWindow == nil {
            let hosting = SettingsContentController(rootView: SettingsView(model: model, updates: updates, navigation: settingsNavigation))
            hosting.sizingOptions = [.preferredContentSize]
            let window = SettingsWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 500))
            window.contentMinSize = NSSize(width: SettingsLayout.minimumWidth, height: 0)
            window.setFrameAutosaveName("LeewaySettings")
            let toolbar = SettingsToolbar(navigation: settingsNavigation, model: model)
            toolbar.install(in: window)
            settingsToolbar = toolbar
            if !window.setFrameUsingName("LeewaySettings") { window.center() }
            window.resizeContent(to: hosting.preferredContentSize, animated: false)
            settingsWindow = NSWindowController(window: window)
        }
        (settingsWindow?.window as? SettingsWindow)?.prepareForOpening()
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        (settingsWindow?.window as? SettingsWindow)?.prepareForOpening()
    }
}

@MainActor
private struct UnavailableUsageProvider: UsageProvider {
    func refresh() async throws -> [AccountUsage] { throw CocoaError(.fileReadUnknown) }
    func saveSettings(_ preferences: AppPreferences, accounts: [AccountUsage]) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}
