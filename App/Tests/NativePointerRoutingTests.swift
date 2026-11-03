import AppKit
import AppModel
import SwiftUI
import XCTest
@testable import LeewayPresentation

@MainActor
final class NativePointerRoutingTests: XCTestCase {
    func testAccountRow_HitTestingDeliversPointerEventsToTheRow() async throws {
        let model = UsageModel(provider: TestProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        let row = try XCTUnwrap(menu.items[0].view as? AccountMenuRow)
        let parent = NSView(frame: row.frame)
        parent.addSubview(row)
        XCTAssertTrue(parent.hitTest(NSPoint(x: row.bounds.midX, y: row.bounds.midY)) === row)
    }

    func testManualAccountList_NativeRowsAllowSelectionAndSupplyDragData() async throws {
        let model = UsageModel(provider: TestProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        model.setAccountOrderMode(.manual)
        let view = NSHostingView(rootView: Form { AccountOrderSettings(model: model, strings: Localizer(language: .english)) }
            .formStyle(.grouped).frame(width: 560, height: 500))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 560, height: 500),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = view
        for _ in 0..<10 { view.layoutSubtreeIfNeeded(); await Task.yield() }
        let outline = try XCTUnwrap(descendant(view, of: NSOutlineView.self))
        let item = try XCTUnwrap(outline.item(atRow: 0))
        XCTAssertTrue(outline.delegate?.outlineView?(outline, shouldSelectItem: item) ?? true)
        XCTAssertNotNil(outline.dataSource?.outlineView?(outline, pasteboardWriterForItem: item) ?? nil)
    }

    private func descendant<T: NSView>(_ root: NSView, of type: T.Type) -> T? {
        if let found = root as? T { return found }
        return root.subviews.lazy.compactMap { self.descendant($0, of: type) }.first
    }
}
