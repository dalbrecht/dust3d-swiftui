import Dust3DDocument
import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

@MainActor final class SurfaceInkDraftTests: XCTestCase {
    @MainActor private final class Admission { var isAvailable = false }
    func testChoosingAndTextEditingRemainDraftOnlyAndCancelInvalidatesRetainedCallbacks() {
        let original = ComponentColorValue.value(DocumentColor(red: 12, green: 34, blue: 56))
        let draft = SurfaceInkDraft(source: original)
        let choose = draft.choosingAction(canEdit: { true })
        let edit = draft.editingAction(canEdit: { true })
        choose(.init(red: 100, green: 120, blue: 140))
        XCTAssertEqual(draft.color.parsedColor, .init(red: 100, green: 120, blue: 140))
        draft.cancel(source: original)
        choose(.init(red: 1, green: 2, blue: 3))
        edit("#FF0000")
        XCTAssertEqual(draft.color.parsedColor, .init(red: 12, green: 34, blue: 56))
        let replacement = draft.choosingAction(canEdit: { true })
        replacement(nil)
        XCTAssertNotNil(draft.color.conversionIssue)
        XCTAssertFalse(draft.canApply)
        draft.editingAction(canEdit: { true })("#010203")
        XCTAssertTrue(draft.canApply)
        draft.editingAction(canEdit: { true })("#80010203")
        XCTAssertFalse(draft.canApply)
    }
    func testUnavailableCallbacksDoNotChangeUnsupportedSourceOrAcquireLaterAdmission() {
        let draft = SurfaceInkDraft(source: .unsupported("future"))
        let admission = Admission()
        let choose = draft.choosingAction(canEdit: { admission.isAvailable })
        let edit = draft.editingAction(canEdit: { admission.isAvailable })
        admission.isAvailable = true
        choose(.init(red: 1, green: 2, blue: 3))
        edit("#010203")
        XCTAssertEqual(draft.color.text, "")
        XCTAssertFalse(draft.canApply)
        draft.cancel(source: .unset)
        XCTAssertFalse(draft.canApply)
    }
}
