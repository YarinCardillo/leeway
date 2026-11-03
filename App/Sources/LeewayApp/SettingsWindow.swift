import AppKit

/// Initial focus belongs to the native window until the person clicks or uses the keyboard.
final class SettingsWindow: NSWindow {
    private var isAwaitingUserInput = true

    convenience init(settingsContent: NSViewController) {
        self.init(contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.initialWidth, height: SettingsLayout.initialHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        contentViewController = settingsContent
        setContentSize(NSSize(width: SettingsLayout.initialWidth, height: SettingsLayout.initialHeight))
        contentMinSize = NSSize(width: SettingsLayout.minimumWidth, height: SettingsLayout.minimumHeight)
    }

    func prepareForOpening() {
        isAwaitingUserInput = true
        _ = super.makeFirstResponder(nil)
        contentView?.layoutSubtreeIfNeeded()
        if let contentView { scrollToTop(contentView) }
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        super.makeFirstResponder(isAwaitingUserInput ? nil : responder)
    }

    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .keyDown].contains(event.type) { allowUserFocus() }
        super.sendEvent(event)
    }

    func allowUserFocus() { isAwaitingUserInput = false }

    private func scrollToTop(_ view: NSView) {
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
            let y = document.isFlipped ? 0 : max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        for child in view.subviews { scrollToTop(child) }
    }
}
