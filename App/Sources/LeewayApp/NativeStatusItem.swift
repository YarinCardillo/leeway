import AppKit
import AppModel
import Observation
import LeewayCore

/// Keeps the status button current without replacing items while a native menu is tracking.
@MainActor
final class NativeStatusItem {
    private static let crossfadeDuration: CFTimeInterval = 0.2
    private static let iconSize: CGFloat = 16
    private static let usageMargin: CGFloat = 2
    private let model: UsageModel
    private let item: NSStatusItem
    private let menu: UsageMenu
    private var shownVerdict: UsageStatus?

    init(model: UsageModel, openSettings: @escaping () -> Void) {
        self.model = model
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = UsageMenu(model: model, openSettings: openSettings)
        item.menu = menu.makeMenu()
        observe()
    }

    /// Loads a preserved-vector Phosphor template; AppKit supplies the menu bar foreground.
    static func icon(status: UsageStatus?) -> NSImage? {
        let name: String
        switch status {
        case .under: name = "trend-down-bold"
        case .over: name = "trend-up-bold"
        default: name = "target-bold"
        }
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: name, withExtension: "svg",
                                    subdirectory: "StatusIcons.xcassets/\(name).imageset")
        let source = url.flatMap(NSImage.init(contentsOf:))
        #else
        let source = Bundle.main.image(forResource: name)
        #endif
        guard let image = source?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: iconSize, height: iconSize)
        image.isTemplate = true
        return image
    }

    static func iconTint(status: UsageStatus?, severity: RiskSeverity?) -> NSColor? {
        nil
    }

    /// The glyph is a verdict, so a change dissolves instead of snapping. Reduce Motion keeps the snap.
    private func crossfadeIfVerdictChanged(_ button: NSStatusBarButton, to status: UsageStatus?) {
        defer { shownVerdict = status }
        guard shownVerdict != nil, shownVerdict != status, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        button.wantsLayer = true
        let fade = CATransition()
        fade.type = .fade
        fade.duration = Self.crossfadeDuration
        button.layer?.add(fade, forKey: "verdictCrossfade")
    }

    private func observe() {
        withObservationTracking {
            updateButton()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func updateButton() {
        guard let button = item.button else { return }
        let strings = Localizer(language: model.preferences.language)
        let account = model.selectedAccount
        crossfadeIfVerdictChanged(button, to: account?.status)
        button.image = Self.icon(status: account?.status)
        button.contentTintColor = Self.iconTint(status: account?.status, severity: account?.severity)
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString(string: "")
        if model.preferences.isMenuBarCompact, model.preferences.showsMenuBarUsage,
           let account, let usage = strings.menuBarUsage(account) {
            let title = NSAttributedString(string: " " + usage, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.attributedTitle = title
            // AppKit pads a title more than an icon; size the item so both sides keep the icon's margin.
            item.length = ceil(Self.iconSize + title.size().width + 2 * Self.usageMargin)
        } else {
            item.length = NSStatusItem.variableLength
        }
        if !model.preferences.isMenuBarCompact, let account {
            button.image = nil
            button.attributedTitle = NSAttributedString(string: strings.menuBarTitle(account), attributes: [
                .foregroundColor: RiskTextColor.color(account.status, severity: account.severity),
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
        }
        button.setAccessibilityLabel("Leeway")
        button.setAccessibilityValue(account.map { strings.menuBarValue($0, pollingMinutes: model.preferences.pollingMinutes) } ?? strings.text("No readings"))
    }

}
