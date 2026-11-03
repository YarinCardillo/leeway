import AppKit
import AppModel
import SwiftUI

/// Native menu items own selection, tracking, keyboard shortcuts and submenu placement.
@MainActor
final class UsageMenu: NSObject, NSMenuDelegate {
    private let model: UsageModel
    private let openSettings: () -> Void
    private var strings: Localizer { Localizer(language: model.preferences.language) }
    /// The meter and the verdict tab share this width, so both end on the same trailing edge.
    private static let contentWidth: CGFloat = 290
    private static let lineGap: CGFloat = 3
    private var accountItems: [String: NSMenuItem] = [:]
    private var highlightedID: String?
    private weak var rootMenu: NSMenu?
    private var updatedItem: NSMenuItem?
    private var openDetailID: String?
    private(set) var readingTimer: Timer?

    init(model: UsageModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = 340
        menu.delegate = self
        rootMenu = menu
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === rootMenu else { return }
        menu.removeAllItems()
        accountItems.removeAll()
        highlightedID = nil
        for account in model.enabledAccounts { menu.addItem(accountItem(account)) }
        if model.enabledAccounts.isEmpty { addEmptyState(to: menu) }
        menu.addItem(.separator())
        let updated = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        updated.isEnabled = false
        menu.addItem(updated)
        updatedItem = updated
        updateReadingTimes()
        if model.refreshError != nil {
            let error = NSMenuItem(title: strings.refreshFailure(hasReading: model.accounts.contains { $0.recordedAt != nil }), action: nil, keyEquivalent: "")
            error.isEnabled = false
            menu.addItem(error)
        }
        addCommands(to: menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === rootMenu else {
            openDetailID = accountItems.first { $0.value.submenu === menu }?.key
            if let openDetailID { setHighlighted(openDetailID) }
            return
        }
        updateReadingTimes()
        guard readingTimer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateReadingTimes() }
        }
        readingTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === rootMenu {
            readingTimer?.invalidate()
            readingTimer = nil
            openDetailID = nil
            setHighlighted(nil)
        } else if accountItems[openDetailID ?? ""]?.submenu === menu {
            openDetailID = nil
            setHighlighted(rootMenu?.highlightedItem.flatMap { item in accountItems.first { $0.value === item }?.key })
        }
    }

    /// AppKit retains the parent selection while its detail submenu is tracking.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard menu === rootMenu else { return }
        if let item {
            let id = accountItems.first { $0.value === item }?.key
            if id != openDetailID { openDetailID = nil }
            setHighlighted(id)
        } else {
            // AppKit can send nil just before opening the submenu. Reconcile after that transition.
            Task { @MainActor [weak self] in
                guard let self, self.readingTimer != nil, self.openDetailID == nil else { return }
                self.setHighlighted(self.rootMenu?.highlightedItem.flatMap { item in
                    self.accountItems.first { $0.value === item }?.key
                })
            }
        }
    }

    private func setHighlighted(_ id: String?) {
        guard id != highlightedID else { return }
        let changed = [highlightedID, id].compactMap { $0 }
        highlightedID = id
        for account in model.enabledAccounts where changed.contains(account.id) {
            guard let item = accountItems[account.id] else { continue }
            (item.view as? AccountMenuRow)?.isHighlighted = account.id == id
        }
    }

    func updateReadingTimes() {
        for account in model.enabledAccounts {
            guard let item = accountItems[account.id] else { continue }
            item.attributedTitle = rowTitle(account)
            (item.view as? AccountMenuRow)?.update(title: item.attributedTitle)
            updateAccessibility(item, account: account)
        }
        updatedItem?.title = strings.updated(model.accounts.compactMap(\.recordedAt).max(), isRefreshing: model.isRefreshing) ?? ""
        updatedItem?.isHidden = updatedItem?.title.isEmpty ?? true
    }

    private func accountItem(_ account: AccountUsage) -> NSMenuItem {
        let item = NSMenuItem(title: account.name, action: nil, keyEquivalent: "")
        item.attributedTitle = rowTitle(account)
        item.isEnabled = true
        item.submenu = detailMenu(account)
        item.view = AccountMenuRow(item: item)
        updateAccessibility(item, account: account)
        accountItems[account.id] = item
        return item
    }

    private func updateAccessibility(_ item: NSMenuItem, account: AccountUsage) {
        item.setAccessibilityLabel("\(account.name), \(strings.status(account))")
        let age = strings.readingAgeLabel(account, pollingMinutes: model.preferences.pollingMinutes)
        item.setAccessibilityValue([strings.usageFacts(account), strings.resetFacts(account), age].compactMap { $0 }.joined(separator: ". "))
    }

    private func rowTitle(_ account: AccountUsage) -> NSAttributedString {
        let title = NSMutableAttributedString(attributedString: headline(account))
        if let meter = NativeUsageMeter.attachment(account: account, width: Self.contentWidth) {
            title.append(NSAttributedString(string: "\n"))
            title.append(styled(meter, spacingBefore: Self.lineGap))
        }
        title.append(NSAttributedString(string: "\n"))
        title.append(caption(account))
        return title
    }

    /// Line 1: the account name, and the verdict in words at the trailing edge.
    private func headline(_ account: AccountUsage) -> NSAttributedString {
        let color = RiskTextColor.verdict(account)
        let line = NSMutableAttributedString(string: account.name,
            attributes: [.font: NSFont.menuFont(ofSize: 13),
                         .foregroundColor: NSColor.labelColor,
                         .paragraphStyle: paragraph()])
        line.append(NSAttributedString(string: "\t" + strings.status(account), attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color, .paragraphStyle: paragraph()]))
        return line
    }

    /// Line 3: regular weight, secondary colour, tabular figures. Nothing here is bold.
    private func caption(_ account: AccountUsage) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let line = NSMutableAttributedString(string: strings.menuCaption(account), attributes: [
            .font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph(spacingBefore: Self.lineGap)])
        if let age = strings.readingAge(account, pollingMinutes: model.preferences.pollingMinutes) {
            line.append(NSAttributedString(string: ", " + age, attributes: [
                .font: font, .foregroundColor: NSColor.systemOrange, .paragraphStyle: paragraph(spacingBefore: Self.lineGap)]))
        }
        return line
    }

    private func styled(_ text: NSAttributedString, spacingBefore: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        result.addAttribute(.paragraphStyle, value: paragraph(spacingBefore: spacingBefore),
                            range: NSRange(location: 0, length: result.length))
        return result
    }

    private func paragraph(spacingBefore: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: Self.contentWidth)]
        style.paragraphSpacingBefore = spacingBefore
        return style
    }

    private func detailMenu(_ account: AccountUsage) -> NSMenu {
        let menu = NSMenu(title: account.name)
        menu.autoenablesItems = false
        menu.delegate = self
        let pin = command("Show in Menu Bar", action: #selector(pinAccount(_:)))
        pin.representedObject = account.id
        pin.state = model.preferences.pinnedID == account.id ? .on : .off
        let insets = DetailInsets.standard
        let selection = ChartSelection()
        let content = NSMenuItem()
        let hosting = NSHostingView(rootView: AccountDetail(account: account, model: model, strings: strings, selection: selection, insets: insets)
            .environment(\.locale, strings.locale))
        hosting.setFrameSize(hosting.fittingSize)
        content.view = hosting
        menu.addItem(content)
        menu.addItem(.separator())
        menu.addItem(pin)
        return menu
    }

    private func addEmptyState(to menu: NSMenu) {
        let title = model.hasRefreshed ? "No accounts found" : "Reading usage"
        let item = NSMenuItem(title: strings.text(title), action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        if model.hasRefreshed {
            let key = model.accounts.isEmpty ? "Sign in with Claude Code or Codex, then choose Refresh Now" : "All accounts are turned off in Settings"
            let hint = NSMenuItem(title: strings.text(key), action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
    }

    private func addCommands(to menu: NSMenu) {
        let automatic = command("Show Most at Risk", action: #selector(showAutomatic))
        automatic.state = model.preferences.pinnedID == nil ? .on : .off
        automatic.isEnabled = !model.enabledAccounts.isEmpty
        menu.addItem(automatic)
        let refresh = command("Refresh Now", action: #selector(refresh), key: "r")
        refresh.isEnabled = !model.isRefreshing
        menu.addItem(refresh)
        menu.addItem(command("Settings…", action: #selector(settings), key: ","))
        menu.addItem(.separator())
        menu.addItem(command("Quit Leeway", action: #selector(quit), key: "q"))
    }

    private func command(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: strings.text(title), action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func pinAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        model.pin(model.preferences.pinnedID == id ? nil : id)
        sender.state = model.preferences.pinnedID == id ? .on : .off
    }
    @objc private func showAutomatic() { model.pin(nil) }
    @objc private func refresh() { Task { await model.refresh() } }
    @objc private func settings() { openSettings() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
