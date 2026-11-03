import AppKit
import XCTest
import SwiftUI
@testable import LeewayPresentation

@MainActor
final class SettingsPlacementTests: XCTestCase {
    private let size = NSSize(width: 560, height: 588)
    private let displays = [
        SettingsWindowPlacement.Display(frame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
                                        visible: NSRect(x: 0, y: 40, width: 1728, height: 1044)),
        SettingsWindowPlacement.Display(frame: NSRect(x: -1440, y: 200, width: 1440, height: 900),
                                        visible: NSRect(x: -1440, y: 240, width: 1440, height: 827))
    ]

    func testFirstOpening_CentersOnPointerDisplayIncludingItsMenuBar() throws {
        for point in [NSPoint(x: -900, y: 500), NSPoint(x: -900, y: 1090)] {
            let frame = try XCTUnwrap(SettingsWindowPlacement.frame(size: size, saved: nil, pointer: point, displays: displays))
            XCTAssertEqual(frame.midX, displays[1].visible.midX)
            XCTAssertEqual(frame.midY, displays[1].visible.midY)
            XCTAssertTrue(displays[1].visible.contains(frame))
        }
    }

    func testSavedPosition_RemainsOnItsDisplayWhenPointerIsElsewhere() throws {
        let saved = NSRect(x: 180, y: 250, width: 640, height: 600)
        let frame = try XCTUnwrap(SettingsWindowPlacement.frame(size: size, saved: saved,
            pointer: NSPoint(x: -900, y: 500), displays: displays))
        XCTAssertEqual(frame, saved)
    }

    func testPartlyOffscreenFrame_IsFittedToTheDisplayWithMostOverlap() throws {
        let saved = NSRect(x: 1500, y: 900, width: 640, height: 600)
        let frame = try XCTUnwrap(SettingsWindowPlacement.frame(size: size, saved: saved,
            pointer: NSPoint(x: -900, y: 500), displays: displays))
        XCTAssertTrue(displays[0].visible.contains(frame))
        XCTAssertEqual(frame.size, saved.size)
    }

    func testDisconnectedDisplay_ReturnsWindowToTheActiveDisplay() throws {
        let saved = NSRect(x: 6000, y: -4000, width: 640, height: 600)
        let frame = try XCTUnwrap(SettingsWindowPlacement.frame(size: size, saved: saved,
            pointer: NSPoint(x: -900, y: 500), displays: displays))
        XCTAssertTrue(displays[1].visible.contains(frame))
        XCTAssertEqual(frame.midX, displays[1].visible.midX)
        XCTAssertEqual(frame.midY, displays[1].visible.midY)
    }

    func testOversizedWindow_FitsEntirelyInsideTheAvailableArea() throws {
        let frame = try XCTUnwrap(SettingsWindowPlacement.frame(size: NSSize(width: 5000, height: 3000), saved: nil,
            pointer: NSPoint(x: 800, y: 1100), displays: displays))
        XCTAssertEqual(frame, displays[0].visible)
    }

    func testNativeRestore_HappensBeforeAutosaveRegistrationAndPreservesUserFrame() throws {
        let name = "LeewayPlacementTests-" + UUID().uuidString
        defer { NSWindow.removeFrame(usingName: name) }
        let source = SettingsWindow(settingsContent: NSHostingController(rootView: Color.clear))
        source.setFrameOrigin(NSPoint(x: 220, y: 180))
        source.saveFrame(usingName: name)
        let restored = SettingsWindow(settingsContent: NSHostingController(rootView: Color.clear))
        restored.restorePlacement(autosaveName: name)
        XCTAssertEqual(restored.frame, source.frame)
        XCTAssertEqual(restored.frameAutosaveName, name)
        restored.setFrameAutosaveName("")
    }

    func testNativeFirstOpening_CentersAfterToolbarSizingBeforeRegisteringAutosave() throws {
        let name = "LeewayPlacementTests-" + UUID().uuidString
        defer { NSWindow.removeFrame(usingName: name) }
        let window = SettingsWindow(settingsContent: NSHostingController(rootView: Color.clear))
        window.setContentSize(NSSize(width: 560, height: 600))
        let point = NSPoint(x: -900, y: 1090)
        window.restorePlacement(autosaveName: name, pointer: point, displays: displays)
        XCTAssertEqual(window.frame.midX, displays[1].visible.midX, accuracy: 0.5)
        XCTAssertEqual(window.frame.midY, displays[1].visible.midY, accuracy: 0.5)
        XCTAssertEqual(window.frameAutosaveName, name)
        window.setFrameAutosaveName("")
    }
}
