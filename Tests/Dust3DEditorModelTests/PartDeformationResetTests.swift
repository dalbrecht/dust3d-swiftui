import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class PartDeformationResetTests: XCTestCase {
    private func makeDocument() throws -> Dust3DDocument {
        let xml = """
            <canvas><parts>
            <part id='model' deformWidth='1.5' deformThickness='0.5' deformUnified='true' locked='true' visible='false'/>
            <part id='profile' target='CutFace' deformWidth='1.5'/>
            <part id='imported' target='ImportedModel' deformWidth='1.5' deformThickness='.25' deformUnified='true'/>
            </parts><components>
            <component id='first-link' linkDataType='partId' linkData='model'/>
            <component id='second-link' linkDataType='partId' linkData='model'/>
            </components></canvas>
            """
        return try Dust3DDocument(snapshotXML: Data(xml.utf8))
    }

    func testResetChangesOnlyOneScaleAndIsAnExactNoOpAtDefault() async throws {
        let source = try makeDocument()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let original = try await session.selectPart("model")
        let widthReset = try await session.resetPartDeformationScale(
            .width, partID: "model", target: CanvasAdjustmentTarget(snapshot: original))
        let afterWidth = try XCTUnwrap(widthReset.selectedPart)
        XCTAssertEqual(afterWidth.deformationScale(.width), 1)
        XCTAssertEqual(afterWidth.deformationScale(.thickness), 0.5)
        XCTAssertEqual(afterWidth.isDeformationUnified, true)
        XCTAssertTrue(afterWidth.isLocked)
        XCTAssertFalse(afterWidth.isVisible)

        let repeated = try await session.resetPartDeformationScale(
            .width, partID: "model", target: CanvasAdjustmentTarget(snapshot: widthReset))
        XCTAssertEqual(repeated.document.encoded(), widthReset.document.encoded())
        XCTAssertEqual(repeated.documentRevision, widthReset.documentRevision)

        let thicknessReset = try await session.resetPartDeformationScale(
            .thickness, partID: "model", target: CanvasAdjustmentTarget(snapshot: repeated))
        XCTAssertEqual(thicknessReset.selectedPart?.deformationScale(.width), 1)
        XCTAssertEqual(thicknessReset.selectedPart?.deformationScale(.thickness), 1)
        XCTAssertEqual(thicknessReset.selectedPart?.isDeformationUnified, true)

        let undoThickness = try await session.undo()
        let undoWidth = try await session.undo()
        XCTAssertEqual(undoThickness.document.encoded(), widthReset.document.encoded())
        XCTAssertEqual(undoWidth.document.encoded(), source.encoded())
        XCTAssertFalse(undoWidth.canUndo)
        let redoWidth = try await session.redo()
        XCTAssertEqual(redoWidth.document.encoded(), widthReset.document.encoded())
    }

    func testResetUsesTheSameSharedOwnerAsThePartInspector() async throws {
        let session = EditorSession()
        _ = try await session.open(data: makeDocument().encoded())
        let singleton = try await session.selectComponents(["first-link"])
        XCTAssertNil(singleton.inspectedPart)
        let shared = try await session.selectComponents(["first-link", "second-link"])
        XCTAssertNil(shared.selectedPart)
        XCTAssertEqual(shared.inspectedPart?.id, "model")
        let edited = try await session.resetPartDeformationScale(
            .width, partID: "model", target: CanvasAdjustmentTarget(snapshot: shared))
        XCTAssertEqual(edited.inspectedPart?.deformationScale(.width), 1)
        XCTAssertEqual(edited.inspectedPart?.deformationScale(.thickness), 0.5)
        XCTAssertEqual(edited.selectedComponentIDs, shared.selectedComponentIDs)
    }

    func testImportedModelResetsWidthAndThicknessIndependently() async throws {
        let source = try makeDocument()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let original = try await session.selectPart("imported")
        let width = try await session.resetPartDeformationScale(
            .width, partID: "imported", target: CanvasAdjustmentTarget(snapshot: original))
        XCTAssertEqual(width.inspectedPart?.deformationScale(.width), 1)
        XCTAssertEqual(width.inspectedPart?.deformationScale(.thickness), 0.25)
        let thickness = try await session.resetPartDeformationScale(
            .thickness, partID: "imported", target: CanvasAdjustmentTarget(snapshot: width))
        XCTAssertEqual(thickness.inspectedPart?.deformationScale(.width), 1)
        XCTAssertEqual(thickness.inspectedPart?.deformationScale(.thickness), 1)
        XCTAssertEqual(thickness.inspectedPart?.isDeformationUnified, true)

        let undoThickness = try await session.undo()
        let undoWidth = try await session.undo()
        XCTAssertEqual(undoThickness.document.encoded(), width.document.encoded())
        XCTAssertEqual(undoWidth.document.encoded(), source.encoded())
    }

    func testResetRejectsStaleAndCutFaceTargets() async throws {
        let source = try makeDocument()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let selected = try await session.selectPart("model")
        let stale = CanvasAdjustmentTarget(snapshot: selected)
        _ = try await session.selectPart("profile")
        _ = try await session.selectPart("model")
        do {
            _ = try await session.resetPartDeformationScale(.width, partID: "model", target: stale)
            XCTFail("Returning to the original part must not revive a stale reset")
        } catch {
            XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment)
        }

        let nonModel = try await session.selectPart("profile")
        do {
            _ = try await session.resetPartDeformationScale(
                .width, partID: "profile", target: CanvasAdjustmentTarget(snapshot: nonModel))
            XCTFail("Cut Face parts do not support this reset")
        } catch {
            // The current role does not authorize this reset.
        }
        let unchanged = try await session.undo()
        XCTAssertEqual(unchanged.document.encoded(), source.encoded())
        XCTAssertFalse(unchanged.canUndo)
        XCTAssertFalse(unchanged.canRedo)
    }
}
