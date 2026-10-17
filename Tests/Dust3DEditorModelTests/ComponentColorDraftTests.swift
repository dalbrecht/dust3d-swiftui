import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class ComponentColorDraftTests: XCTestCase {
    func testInitialDraftSeparatesUnsetUnsupportedAndValidSources() {
        for source: ComponentColorValue in [.unset, .unsupported("future"), .unsupported("")] {
            let draft = ComponentColorDraft(source: source)
            XCTAssertEqual(draft.text, "")
            XCTAssertNil(draft.parsedColor)
            XCTAssertNil(draft.conversionIssue)
            XCTAssertFalse(draft.canApply)
            XCTAssertEqual(draft.pickerColor, DocumentColor(red: 255, green: 255, blue: 255))
        }
        let color = DocumentColor(red: 17, green: 34, blue: 51, alpha: 128)
        let draft = ComponentColorDraft(source: .value(color))
        XCTAssertEqual(draft.text, "#80112233")
        XCTAssertEqual(draft.parsedColor, color)
        XCTAssertEqual(draft.pickerColor, color)
        XCTAssertTrue(draft.canApply)
    }

    func testConversionFailurePreservesTextAndBlocksApplyUntilEditingChoosingOrReset() {
        let color = DocumentColor(red: 1, green: 2, blue: 3)
        let original = ComponentColorDraft(source: .value(color))
        let failed = original.choosing(nil)
        XCTAssertEqual(failed.text, original.text)
        XCTAssertEqual(failed.conversionIssue, .unsupportedColorConversion)
        XCTAssertTrue(failed.conversionIssue?.message.contains("sRGB") == true)
        XCTAssertFalse(failed.canApply)
        let edited = failed.editing("#FF010203")
        XCTAssertNil(edited.conversionIssue)
        XCTAssertTrue(edited.canApply)
        XCTAssertEqual(edited.parsedColor, color)
        let invalid = edited.editing("future")
        XCTAssertNil(invalid.parsedColor)
        XCTAssertTrue(invalid.canApply, "Invalid nonempty hex reaches the controller's explicit validation error")
        XCTAssertFalse(invalid.editing("").canApply)
        let chosen = failed.choosing(DocumentColor(red: 0, green: 255, blue: 0, alpha: 0))
        XCTAssertEqual(chosen.text, "#0000FF00")
        XCTAssertNil(chosen.conversionIssue)
        XCTAssertTrue(chosen.canApply)
        XCTAssertEqual(ComponentColorDraft(source: .value(color)), original)
    }

    func testSourceSummaryBoundsUnicodeTextWithoutChangingSource() {
        XCTAssertEqual(ComponentColorDraft.sourceSummary(""), "(empty)")
        XCTAssertEqual(ComponentColorDraft.sourceSummary("future"), "future")
        let exact = String(repeating: "🟦", count: 80)
        XCTAssertEqual(ComponentColorDraft.sourceSummary(exact), exact)
        let long = exact + String(repeating: "🟩", count: 1000)
        XCTAssertEqual(ComponentColorDraft.sourceSummary(long), exact + "…")
        XCTAssertEqual(long.count, 1080)
        let combining = "e" + String(repeating: "\u{0301}", count: 1000)
        let summary = ComponentColorDraft.sourceSummary(combining)
        XCTAssertLessThanOrEqual(summary.utf8.count, 328)
        XCTAssertTrue(summary.hasSuffix("…"))
    }
}
