import CoreGraphics

/// The left edge of a menu item's title, which AppKit moves right while its state check mark is shown.
///
/// AppKit offers no API for this: NSMenuItemCell reports the same title origin for both states, so the two
/// values are measured from the rendered menu on macOS 14 to 26 and used to align custom content with it.
struct DetailInsets {
    let unpinned: CGFloat
    let pinned: CGFloat

    static let standard = DetailInsets(unpinned: 16, pinned: 24)

    func leading(isPinned: Bool) -> CGFloat { isPinned ? pinned : unpinned }
}
