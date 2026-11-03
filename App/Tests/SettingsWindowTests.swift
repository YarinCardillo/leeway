import AppKit
import XCTest
@testable import LeewayPresentation

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testOpening_RejectsAutomaticFieldFocusUntilUserInteraction() {
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440), styleMask: [.titled], backing: .buffered, defer: true)
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 180, height: 22))
        window.contentView?.addSubview(field)
        window.prepareForOpening()
        _ = window.makeFirstResponder(field)
        XCTAssertTrue(window.firstResponder === window)
        window.allowUserFocus()
        _ = window.makeFirstResponder(field)
        XCTAssertFalse(window.firstResponder === window)
        window.prepareForOpening()
        XCTAssertTrue(window.firstResponder === window)
    }
}

extension SettingsWindowTests {
    func testOpening_ScrollsTheNativeFormContainerToTheTop() {
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440), styleMask: [.titled], backing: .buffered, defer: true)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 1000))
        window.contentView?.addSubview(scroll)
        scroll.contentView.scroll(to: .zero)
        window.prepareForOpening()
        XCTAssertEqual(scroll.documentVisibleRect.maxY, 1000, accuracy: 1)
        XCTAssertTrue(window.firstResponder === window)
    }
}


extension SettingsWindowTests {
    func testPaneResize_KeepsTopEdgeAndWidthForEachContentHeight() {
        let window = SettingsWindow(contentRect: NSRect(x: 100, y: 200, width: 560, height: 500),
                                    styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        let original = window.frame
        for height in [550.0, 240.0, 180.0, 285.0] {
            window.resizeContent(to: NSSize(width: 520, height: height), animated: false)
            XCTAssertEqual(window.frame.maxY, original.maxY, accuracy: 0.5)
            XCTAssertEqual(window.frame.width, original.width, accuracy: 0.5)
            XCTAssertEqual(window.contentView!.frame.height, height, accuracy: 0.5)
        }
    }

    func testPaneResize_BoundsLongAccountsToVisibleScreen() {
        let window = SettingsWindow(contentRect: NSRect(x: 100, y: 200, width: 560, height: 500),
                                    styleMask: [.titled], backing: .buffered, defer: true)
        let originalTop = window.frame.maxY
        window.resizeContent(to: NSSize(width: 560, height: 5000), animated: false)
        XCTAssertLessThanOrEqual(window.frame.height, window.screen!.visibleFrame.height)
        XCTAssertGreaterThanOrEqual(window.frame.minY, window.screen!.visibleFrame.minY)
        XCTAssertEqual(window.frame.maxY, originalTop, accuracy: 0.5)
    }
}
