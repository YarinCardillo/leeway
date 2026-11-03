import AppKit

/// Presentation only: NSMenu retains tracking, submenu placement and keyboard navigation.
@MainActor
final class AccountMenuRow: NSView {
    private let cell: NSMenuItemCell
    private var hoverTracking: NSTrackingArea?
    var onHover: ((Bool) -> Void)?
    private(set) var isPointerInside = false
    var isHighlighted = false { didSet { needsDisplay = true } }
    var selectionColor: NSColor {
        NSColor.unemphasizedSelectedContentBackgroundColor.blended(withFraction: 0.12, of: .labelColor)!
    }
    override var isFlipped: Bool { true }

    init(item: NSMenuItem) {
        cell = NSMenuItemCell(textCell: item.title)
        // A presentation copy keeps sizing independent of the custom item view.
        let content = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
        content.attributedTitle = item.attributedTitle
        content.submenu = NSMenu()
        cell.menuItem = content
        cell.calcSize()
        super.init(frame: NSRect(origin: .zero, size: cell.cellSize))
        autoresizingMask = [.width]
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    func update(title: NSAttributedString?) {
        cell.menuItem?.attributedTitle = title
        cell.needsSizing = true
        cell.calcSize()
        setFrameSize(NSSize(width: max(frame.width, cell.cellSize.width), height: cell.cellSize.height))
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        onHover?(false)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            selectionColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 5, yRadius: 5).fill()
        }
        guard let title = cell.menuItem?.attributedTitle else { return }
        var rect = cell.titleRect(forBounds: bounds)
        rect.origin.y = (bounds.height - title.size().height) / 2
        rect.size.height = title.size().height
        title.draw(in: rect)
        let arrow = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.secondaryLabelColor]))
        arrow?.draw(in: NSRect(x: bounds.maxX - 18, y: bounds.midY - 6, width: 7, height: 12))
    }
}
