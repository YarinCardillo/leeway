import AppKit
import AppModel
import XCTest
@testable import LeewayPresentation

@MainActor
final class NativeMenuTests: XCTestCase {
    func testAccounts_HaveNativeSubmenusAndOnlyAccountsCustomizeSelection() async {
        let model = UsageModel(provider: MockUsageProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        let row = menu.items.first!
        XCTAssertNotNil(row.view)
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
        XCTAssertNil(NativeStatusItem.iconTint(status: .under, severity: nil))
        XCTAssertNil(NativeStatusItem.iconTint(status: .over, severity: .amber))
        XCTAssertNil(NativeStatusItem.iconTint(status: .over, severity: .red))
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
    func testSubmenuTracking_PreservesSemanticColoursUntilRootCloses() async throws {
        let model = UsageModel(provider: MockUsageProvider(now: Date().addingTimeInterval(-7200)), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        let row = menu.items[0]
        let detail = try XCTUnwrap(row.submenu)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                let original = row.attributedTitle!
                builder.menu(menu, willHighlight: row)
                builder.menuWillOpen(detail)
                builder.menu(menu, willHighlight: nil)
                builder.menu(detail, willHighlight: detail.items.last)
                let title = row.attributedTitle!
                title.enumerateAttributes(in: NSRange(location: 0, length: title.length)) { attributes, _, _ in
                    if attributes[.font] != nil {
                        XCTAssertNotEqual(attributes[.foregroundColor] as? NSColor, .selectedMenuItemTextColor)
                    }
                }
                XCTAssertEqual(original.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                               title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
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

extension NativeMenuTests {
    func testUsageMeter_TargetTicksRemainVisibleAboveOverlappingFills() throws {
        var account = AccountUsage(id: "overlap", name: "Work", source: "claude", weeklyUsed: 96,
                                   fiveHourUsed: nil, reset: nil, fiveHourReset: nil, weekForecast: 70,
                                   recentForecast: 116, recordedAt: nil, history: [])
        account.targetLow = 75
        account.targetHigh = 100
        let title = try XCTUnwrap(NativeUsageMeter.attachment(account: account, width: 200))
        let attachment = try XCTUnwrap(title.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        let image = try XCTUnwrap((attachment.attachmentCell as? NSTextAttachmentCell)?.image)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
                for fraction in [0.75, 1.0] {
                    let x = min(bitmap.pixelsWide - 2, Int(Double(bitmap.pixelsWide) * fraction))
                    XCTAssertGreaterThan(bitmap.colorAt(x: x, y: 0)!.alphaComponent, 0.9)
                }
                XCTAssertLessThan(bitmap.colorAt(x: 100, y: 0)!.alphaComponent, 0.1)
            }
        }
    }
}


extension NativeMenuTests {
    func testAccountHighlight_UsesNeutralSelectionAndLeavesCommandsNative() async throws {
        let model = UsageModel(provider: MockUsageProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        let row = menu.items[0]
        let view = try XCTUnwrap(row.view as? AccountMenuRow)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                builder.menu(menu, willHighlight: row)
                XCTAssertTrue(view.isHighlighted)
                let neutral = view.selectionColor.usingColorSpace(.sRGB)!
                let native = NSColor.unemphasizedSelectedContentBackgroundColor.usingColorSpace(.sRGB)!
                XCTAssertEqual(neutral.redComponent, neutral.greenComponent, accuracy: 0.001)
                XCTAssertEqual(neutral.greenComponent, neutral.blueComponent, accuracy: 0.001)
                XCTAssertGreaterThan(abs(neutral.redComponent - native.redComponent), 0.08)
                XCTAssertNotEqual(view.selectionColor, .selectedContentBackgroundColor)
                builder.menu(menu, willHighlight: menu.items.last)
                XCTAssertFalse(view.isHighlighted)
            }
        }
        for item in menu.items where !item.keyEquivalent.isEmpty { XCTAssertNil(item.view) }
    }
}

extension NativeMenuTests {
    func testAccountRow_DrawsMultilineContentWhenInstalledAsItemView() async throws {
        let model = UsageModel(provider: MockUsageProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        let view = try XCTUnwrap(menu.items[0].view as? AccountMenuRow)
        XCTAssertGreaterThan(view.bounds.height, 40)
        let image = NSImage(size: view.bounds.size, flipped: true) { rect in
            MainActor.assumeIsolated { view.draw(rect) }
            return true
        }
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        let hasContent = (0..<bitmap.pixelsHigh).contains { y in
            (0..<bitmap.pixelsWide).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
        }
        XCTAssertTrue(hasContent)
    }
}


extension NativeMenuTests {
    func testAccountHighlight_AllVerdictsKeepTextAndMeterColours() async throws {
        let model = UsageModel(provider: MockUsageProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                for row in menu.items where row.hasSubmenu {
                    let original = row.attributedTitle!
                    let attachment = meter(in: row)
                    builder.menu(menu, willHighlight: row)
                    XCTAssertTrue(original.isEqual(to: row.attributedTitle!))
                    XCTAssertTrue(attachment === meter(in: row))
                    builder.menu(menu, willHighlight: menu.items.last)
                }
            }
        }
    }
}

extension NativeMenuTests {
    func testAccountRow_LongerUpdatedCaptionExpandsWithoutShrinkingMenuWidth() async throws {
        let model = UsageModel(provider: MockUsageProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        let row = menu.items[0]
        let view = try XCTUnwrap(row.view as? AccountMenuRow)
        let originalWidth = view.frame.width
        let longer = NSMutableAttributedString(attributedString: row.attributedTitle!)
        longer.append(NSAttributedString(string: ", reading is 120 minutes old", attributes: [.font: NSFont.systemFont(ofSize: 11)]))
        view.update(title: longer)
        XCTAssertGreaterThan(view.frame.width, originalWidth)
        let expandedWidth = view.frame.width + 30
        view.setFrameSize(NSSize(width: expandedWidth, height: view.frame.height))
        view.update(title: row.attributedTitle)
        XCTAssertEqual(view.frame.width, expandedWidth)
    }
}

extension NativeMenuTests {
    func testAccountPointerHover_HighlightsImmediatelyAndRetainsOpenSubmenu() async throws {
        let model = UsageModel(provider: MockUsageProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        let row = menu.items[0]
        let view = try XCTUnwrap(row.view as? AccountMenuRow)
        view.updateTrackingAreas()
        XCTAssertTrue(view.trackingAreas.contains { $0.options.contains([.mouseEnteredAndExited, .activeAlways, .inVisibleRect]) })
        let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        view.mouseEntered(with: event)
        XCTAssertTrue(view.isHighlighted)
        view.mouseExited(with: event)
        XCTAssertFalse(view.isHighlighted)
        view.mouseEntered(with: event)
        builder.menuWillOpen(try XCTUnwrap(row.submenu))
        view.mouseExited(with: event)
        XCTAssertTrue(view.isHighlighted)
        builder.menuDidClose(menu)
        XCTAssertFalse(view.isHighlighted)
    }
}

extension NativeMenuTests {
    func testAccountPointerHover_NativeNilHighlightDoesNotErasePointerSelection() async throws {
        let model = UsageModel(provider: MockUsageProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        builder.menuWillOpen(menu)
        defer { builder.menuDidClose(menu) }
        let view = try XCTUnwrap(menu.items[0].view as? AccountMenuRow)
        let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        view.mouseEntered(with: event)
        builder.menu(menu, willHighlight: nil)
        await Task.yield()
        XCTAssertTrue(view.isHighlighted)
    }
}

extension NativeMenuTests {
    func testPendingRead_OpenMenuUpdatesWhenTypedFailureArrivesWithoutAgeTimer() async throws {
        let provider = MenuReadingProvider()
        let model = UsageModel(provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        provider.shouldSuspend = true
        let refresh = Task { await model.refresh() }
        while !provider.hasStarted { await Task.yield() }
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        builder.menuWillOpen(menu)
        defer { builder.menuDidClose(menu) }
        let row = menu.items[0]
        XCTAssertTrue(row.attributedTitle!.string.contains("Reading usage"))
        provider.finish()
        await refresh.value
        for _ in 0..<100 where row.attributedTitle!.string.contains("Reading usage") { await Task.yield() }
        XCTAssertTrue(row.attributedTitle!.string.contains("read_error.timeout"))
        XCTAssertFalse(row.attributedTitle!.string.contains("Reading usage"))
    }

    func testPointerHover_OlderNilCallbackCannotOverrideNewKeyboardCommand() async throws {
        let model = UsageModel(provider: MockUsageProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        builder.menuWillOpen(menu)
        defer { builder.menuDidClose(menu) }
        let view = try XCTUnwrap(menu.items[0].view as? AccountMenuRow)
        let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        view.mouseEntered(with: event)
        builder.menu(menu, willHighlight: nil)
        builder.menu(menu, willHighlight: menu.items.last)
        await Task.yield()
        XCTAssertFalse(view.isHighlighted)
    }

    func testStatusAccount_MenuAndSettingsUseOnePreferenceIndependentOfRowOrder() async throws {
        let model = UsageModel(provider: TestProvider(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.refresh()
        model.setAccountOrderMode(.manual)
        model.moveAccounts(fromOffsets: [1], toOffset: 0)
        let builder = UsageMenu(model: model, openSettings: {})
        let menu = builder.makeMenu()
        builder.menuNeedsUpdate(menu)
        builder.menuWillOpen(menu)
        defer { builder.menuDidClose(menu) }
        let automatic = try XCTUnwrap(menu.items.first { $0.title == "Show Most at Risk" })
        model.pin("low") // The Settings picker uses the same action and preference.
        for _ in 0..<100 where automatic.state != .off { await Task.yield() }
        XCTAssertEqual(automatic.state, .off)
        XCTAssertEqual(model.preferences.pinnedID, "low")
        menu.performActionForItem(at: menu.index(of: automatic))
        XCTAssertNil(model.preferences.pinnedID)
        XCTAssertEqual(model.selectedAccount?.id, "high")
        XCTAssertEqual(model.enabledAccounts.map(\.id), ["low", "high"])
    }
}

@MainActor
private final class MenuReadingProvider: AppModel.UsageProvider {
    var shouldSuspend = false
    var hasStarted = false
    private var continuation: CheckedContinuation<[AccountUsage], Never>?
    func refresh() async throws -> [AccountUsage] {
        if shouldSuspend {
            hasStarted = true
            return await withCheckedContinuation { continuation = $0 }
        }
        var missing = TestProvider.readings[0]
        missing.weeklyUsed = nil
        return [missing]
    }
    func finish() {
        var failed = TestProvider.readings[0]
        failed.weeklyUsed = nil
        failed.error = .timeout
        continuation?.resume(returning: [failed])
        continuation = nil
    }
}
