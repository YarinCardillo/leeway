import AppKit
import SwiftUI

/// Initial focus belongs to the native window until the person clicks or uses the keyboard.
final class SettingsWindow: NSWindow {
    private var isAwaitingUserInput = true

    func prepareForOpening() {
        isAwaitingUserInput = true
        _ = super.makeFirstResponder(nil)
        contentView?.layoutSubtreeIfNeeded()
        if let contentView { scrollToTop(contentView) }
    }

    /// Applies each pane's ideal height using the native frame animation, anchored at the top edge.
    func resizeContent(to size: NSSize, animated: Bool = true) {
        guard size.height > 0 else { return }
        let chrome = frame.height - contentRect(forFrameRect: frame).height
        let maximum = (screen ?? NSScreen.main).map { min($0.visibleFrame.height, frame.maxY - $0.visibleFrame.minY) }
            ?? size.height + chrome
        let height = min(ceil(size.height) + chrome, maximum)
        let target = NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        guard abs(target.height - frame.height) > 0.5 else { return }
        setFrame(target, display: true, animate: animated && isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
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


/// SwiftUI publishes the ideal size, while AppKit controls the window's frame and position.
final class SettingsContentController<Content: View>: NSHostingController<Content> {
    override var preferredContentSize: NSSize {
        didSet { (view.window as? SettingsWindow)?.resizeContent(to: preferredContentSize) }
    }
}
