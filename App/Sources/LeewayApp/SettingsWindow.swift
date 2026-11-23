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

    /// Restores before registering autosave, so setup cannot persist a provisional frame.
    func restorePlacement(autosaveName: String, pointer: NSPoint = NSEvent.mouseLocation,
                          displays: [SettingsWindowPlacement.Display]? = nil) {
        let hasSavedFrame = setFrameUsingName(autosaveName)
        place(saved: hasSavedFrame ? frame : nil, pointer: pointer, displays: displays ?? Self.displays)
        setFrameAutosaveName(autosaveName)
    }

    func prepareForOpening() {
        place(saved: frame, pointer: NSEvent.mouseLocation, displays: Self.displays)
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
        // The window frame view has no superview, so it hit-tests in window coordinates.
        if event.type == .leftMouseDown, endsEditing(forClickOn: contentView?.superview?.hitTest(event.locationInWindow)) {
            _ = makeFirstResponder(nil)
        }
        super.sendEvent(event)
    }

    func allowUserFocus() { isAwaitingUserInput = false }

    /// Whether a click ends the text editing in progress. A click anywhere but on a text input ends it, so the
    /// caret does not stay in a field the person has left; a click on a text input is left to AppKit.
    func endsEditing(forClickOn hit: NSView?) -> Bool {
        guard let editor = firstResponder as? NSTextView, editor.isFieldEditor else { return false }
        guard let hit else { return true }
        return !sequence(first: hit, next: \.superview).contains { $0 is NSTextField || $0 is NSTextView }
    }

    private static var displays: [SettingsWindowPlacement.Display] {
        NSScreen.screens.map { SettingsWindowPlacement.Display(frame: $0.frame, visible: $0.visibleFrame) }
    }

    private func place(saved: NSRect?, pointer: NSPoint, displays: [SettingsWindowPlacement.Display]) {
        guard let position = SettingsWindowPlacement.frame(size: frame.size, saved: saved,
            pointer: pointer, displays: displays), position != frame else { return }
        setFrame(position, display: false)
    }

    private func scrollToTop(_ view: NSView) {
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
            let y = document.isFlipped ? 0 : max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        for child in view.subviews { scrollToTop(child) }
    }
}
