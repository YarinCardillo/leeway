import AppModel
import XCTest

final class EditingAndNavigationTests: XCTestCase {
    func testRenameDraft_PreservesSpacesDuringTyping_AndTrimsOnlyOnCommit() {
        var draft = AccountNameDraft("Account")
        draft.update("Personal ")
        XCTAssertEqual(draft.text, "Personal ")
        draft.update("Personal account ")
        XCTAssertEqual(draft.acceptedName, "Personal account")
        draft.update("  ")
        XCTAssertNil(draft.acceptedName)
    }

    func testArrowNavigation_ReachesEveryFooterCommand() {
        let order = MenuNavigation.actions(accountIDs: ["one"], canRefresh: true)
        XCTAssertEqual(order, [.account("one"), .automatic, .refresh, .settings, .quit])
        XCTAssertEqual(MenuNavigation.move(from: .account("one"), forward: true, in: order), .automatic)
        XCTAssertEqual(MenuNavigation.move(from: .refresh, forward: true, in: order), .settings)
        XCTAssertEqual(MenuNavigation.move(from: nil, forward: false, in: order), .quit)
    }
}

extension EditingAndNavigationTests {
    func testRenameReturn_CommitsTrimmedDraftAndEndsEditing() {
        var draft = AccountNameDraft("Work")
        draft.update(" Personal ")
        XCTAssertEqual(draft.finishEditing(commit: true), "Personal")
        XCTAssertEqual(draft.text, "Personal")
        XCTAssertFalse(draft.isEditing)
    }

    func testRenameEscape_RevertsDraftAndEndsEditing() {
        var draft = AccountNameDraft("Work")
        draft.update("Personal")
        XCTAssertTrue(draft.isEditing)
        XCTAssertNil(draft.finishEditing(commit: false))
        XCTAssertEqual(draft.text, "Work")
        XCTAssertFalse(draft.isEditing)
    }
}

extension EditingAndNavigationTests {
    func testRenameEscape_FollowingFocusLossDoesNotCommitRevertedText() {
        var draft = AccountNameDraft("Work")
        draft.update("Personal")
        XCTAssertNil(draft.finishEditing(commit: false))
        XCTAssertNil(draft.finishEditing(commit: true))
        XCTAssertEqual(draft.text, "Work")
    }
}
