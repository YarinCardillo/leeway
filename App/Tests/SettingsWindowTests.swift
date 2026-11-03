import AppKit
import XCTest
import SwiftUI
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
    // Owner revision: pane content scrolls inside a stable, user-resizable window.
    func testStandardSize_ContainsTallSettingsAndHasUsableMinimums() {
        let controller = NSHostingController(rootView: Color.clear)
        let window = SettingsWindow(settingsContent: controller)
        XCTAssertEqual(window.contentView!.frame.size, NSSize(width: 560, height: 500))
        XCTAssertEqual(window.contentMinSize, NSSize(width: 520, height: 440))
    }

    func testPanePreferredSize_PreservesUserChosenWindowFrame() {
        let controller = NSHostingController(rootView: Color.clear)
        let window = SettingsWindow(settingsContent: controller)
        window.setContentSize(NSSize(width: 640, height: 480))
        let visible = NSScreen.screens[0].visibleFrame
        window.setFrameOrigin(NSPoint(x: visible.minX + 40, y: visible.minY + 40))
        let original = window.frame
        for height in [220.0, 2400, 180, 850] {
            controller.preferredContentSize = NSSize(width: 520, height: height)
            window.prepareForOpening()
            XCTAssertEqual(window.frame, original)
        }
    }
}

extension SettingsWindowTests {
    func testOpening_OffscreenWindowReturnsToAVisibleDisplay() {
        let window = SettingsWindow(contentRect: NSRect(x: -10000, y: -10000, width: 560, height: 500),
            styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.prepareForOpening()
        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.contains(window.frame) })
    }
}
