import AppKit
import AppModel
import XCTest
@testable import LeewayPresentation

@MainActor
final class NativeMenuTests: XCTestCase {
    func testAccounts_HaveNativeSubmenusAndNoCustomSelectionViews() async {
        let model = UsageModel(provider: MockUsageProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        let row = menu.items.first!
        XCTAssertNil(row.view)
        XCTAssertNotNil(row.submenu)
        XCTAssertTrue(row.attributedTitle!.string.contains("resets"))
        let pin = row.submenu!.items.last!
        XCTAssertNil(pin.view)
        XCTAssertEqual(pin.title, "Show in Menu Bar")
        XCTAssertNotNil(pin.action)
    }
}

extension NativeMenuTests {
    func testNativeAttributedRows_AllocateHeightForBothLines() {
        let single = NSMenu()
        let one = NSMenuItem(title: "Work", action: nil, keyEquivalent: "")
        one.attributedTitle = NSAttributedString(string: "Work", attributes: [.font: NSFont.menuFont(ofSize: 13)])
        single.addItem(one)
        let multiple = NSMenu()
        let two = NSMenuItem(title: "Work", action: nil, keyEquivalent: "")
        two.attributedTitle = NSAttributedString(string: "Work\n62% used", attributes: [.font: NSFont.menuFont(ofSize: 13)])
        multiple.addItem(two)
        XCTAssertGreaterThan(multiple.size.height, single.size.height + 8)
    }
}

extension NativeMenuTests {
    func testStatusGlyph_AllVerdictsLoadDistinctVectorTemplates() throws {
        let under = try XCTUnwrap(NativeStatusItem.icon(status: .under))
        let target = try XCTUnwrap(NativeStatusItem.icon(status: .onTarget))
        let over = try XCTUnwrap(NativeStatusItem.icon(status: .over))
        for image in [under, target, over] {
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: 16, height: 16))
        }
        XCTAssertNotEqual(under.tiffRepresentation, target.tiffRepresentation)
        XCTAssertNotEqual(target.tiffRepresentation, over.tiffRepresentation)
        XCTAssertNil(NativeStatusItem.iconTint(status: .onTarget, severity: nil))
        XCTAssertEqual(NativeStatusItem.iconTint(status: .under, severity: nil), .controlAccentColor)
        XCTAssertEqual(NativeStatusItem.iconTint(status: .over, severity: .amber), .systemOrange)
        XCTAssertEqual(NativeStatusItem.iconTint(status: .over, severity: .red), .systemRed)
    }
}

extension NativeMenuTests {
    private func meterAccount() -> AccountUsage {
        AccountUsage(id: "work", name: "Work", source: "claude", weeklyUsed: 62, fiveHourUsed: nil, reset: nil,
                     fiveHourReset: nil, weekForecast: 70, recentForecast: 84, recordedAt: nil, history: [])
    }

    func testUsageMeter_DrawsTheForecastMeterInBothAppearances() throws {
        let account = meterAccount()
        let value = try XCTUnwrap(NativeUsageMeter.attachment(account: account, width: 290))
        let attachment = try XCTUnwrap(value.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        let cell = try XCTUnwrap(attachment.attachmentCell as? NSTextAttachmentCell)
        let image = try XCTUnwrap(cell.image)
        XCTAssertEqual(image.size, NSSize(width: 290, height: NativeUsageMeter.height))
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
                let opaque = (0..<bitmap.pixelsHigh).contains { y in
                    (0..<bitmap.pixelsWide).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
                }
                XCTAssertTrue(opaque, "\(name.rawValue) draws nothing")
            }
        }
    }

    func testUsageMeter_NoReading_HasNoMeter() {
        var account = meterAccount()
        account.weeklyUsed = nil
        XCTAssertNil(NativeUsageMeter.attachment(account: account, width: 290))
    }
}


extension NativeMenuTests {
    func testSubmenuTracking_KeepsAllParentTextSelectedUntilRootCloses() async throws {
        let model = UsageModel(provider: MockUsageProvider(now: Date().addingTimeInterval(-7200)), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        let row = menu.items[0]
        let detail = try XCTUnwrap(row.submenu)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                builder.menu(menu, willHighlight: row)
                builder.menuWillOpen(detail)
                builder.menu(menu, willHighlight: nil)
                builder.menu(detail, willHighlight: detail.items.last)
                let title = row.attributedTitle!
                title.enumerateAttributes(in: NSRange(location: 0, length: title.length)) { attributes, _, _ in
                    if attributes[.font] != nil {
                        XCTAssertEqual(attributes[.foregroundColor] as? NSColor, .selectedMenuItemTextColor)
                    }
                }
                builder.menu(menu, willHighlight: menu.items[1])
                XCTAssertNotEqual(row.attributedTitle!.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                                  .selectedMenuItemTextColor)
                builder.menuDidClose(menu)
            }
        }
    }

    func testAgeTimer_OnlyRunsWhileRootMenuIsOpen() async {
        let model = UsageModel(provider: MockUsageProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        XCTAssertNil(builder.readingTimer)
        builder.menuWillOpen(menu)
        XCTAssertEqual(builder.readingTimer?.isValid, true)
        let timer = builder.readingTimer
        builder.menuWillOpen(menu)
        XCTAssertTrue(builder.readingTimer === timer)
        let row = menu.items[0]
        builder.menuDidClose(menu)
        let attachment = meter(in: row)
        timer?.fire()
        XCTAssertTrue(attachment === meter(in: row))
        XCTAssertNil(builder.readingTimer)
        XCTAssertEqual(timer?.isValid, false)
    }
}


extension NativeMenuTests {
    func testLeavingAccountWithoutOpeningSubmenu_RestoresUnselectedText() async {
        let model = UsageModel(provider: MockUsageProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        builder.menuWillOpen(menu)
        let row = menu.items[0]
        builder.menu(menu, willHighlight: row)
        builder.menu(menu, willHighlight: nil)
        await Task.yield()
        XCTAssertEqual(row.attributedTitle!.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .labelColor)
        builder.menuDidClose(menu)
    }
}


extension NativeMenuTests {
    private func meter(in item: NSMenuItem) -> NSTextAttachment? {
        guard let title = item.attributedTitle, let index = title.string.firstIndex(of: "\u{fffc}") else { return nil }
        return title.attribute(.attachment, at: index.utf16Offset(in: title.string), effectiveRange: nil) as? NSTextAttachment
    }
}
