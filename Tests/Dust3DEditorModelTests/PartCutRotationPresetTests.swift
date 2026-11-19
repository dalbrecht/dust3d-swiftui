import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class PartCutRotationPresetTests: XCTestCase {
    private func makeDocument() throws -> Dust3DDocument {
        let xml = """
            <canvas><parts>
            <part id='a' cutRotation='unsupported' visible='false' locked='true'/>
            <part id='b' cutRotation='0.25'/>
            <part id='profile' target='CutFace' cutRotation='0.25'/>
            <part id='imported' target='ImportedModel' cutRotation='0.5' importedModelId='asset'/>
            </parts><components>
            <component id='first-link' linkDataType='partId' linkData='a'/>
            <component id='second-link' linkDataType='partId' linkData='a'/>
            </components></canvas>
            """
        return try Dust3DDocument(snapshotXML: Data(xml.utf8))
    }

    func testPresetsAreAbsoluteAndRetainOrdinaryPartPropertyHistory() async throws {
        XCTAssertEqual(PartCutRotationPreset.negativeQuarterTurn.halfTurns, -0.5)
        XCTAssertEqual(PartCutRotationPreset.zero.halfTurns, 0)
        XCTAssertEqual(PartCutRotationPreset.positiveQuarterTurn.halfTurns, 0.5)

        let source = try makeDocument()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let original = try await session.selectPart("a")
        XCTAssertNil(original.parts.first { $0.id == "a" }?.cutRotation)
        let negative = try await session.setPartCutRotationPreset(
            .negativeQuarterTurn, partID: "a", target: CanvasAdjustmentTarget(snapshot: original))
        XCTAssertEqual(negative.parts.first { $0.id == "a" }?.cutRotation, -0.5)
        XCTAssertEqual(negative.parts.first { $0.id == "b" }?.cutRotation, 0.25)

        let repeated = try await session.setPartCutRotationPreset(
            .negativeQuarterTurn, partID: "a", target: CanvasAdjustmentTarget(snapshot: negative))
        XCTAssertEqual(repeated.document.encoded(), negative.document.encoded())
        XCTAssertEqual(repeated.documentRevision, negative.documentRevision)

        let positive = try await session.setPartCutRotationPreset(
            .positiveQuarterTurn, partID: "a", target: CanvasAdjustmentTarget(snapshot: repeated))
        XCTAssertEqual(positive.parts.first { $0.id == "a" }?.cutRotation, 0.5)
        let zero = try await session.setPartCutRotationPreset(
            .zero, partID: "a", target: CanvasAdjustmentTarget(snapshot: positive))
        XCTAssertEqual(zero.parts.first { $0.id == "a" }?.cutRotation, 0)

        let undoZero = try await session.undo()
        let undoPositive = try await session.undo()
        let undoNegative = try await session.undo()
        XCTAssertEqual(undoZero.document.encoded(), positive.document.encoded())
        XCTAssertEqual(undoPositive.document.encoded(), negative.document.encoded())
        XCTAssertEqual(undoNegative.document.encoded(), source.encoded())
        XCTAssertFalse(undoNegative.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), negative.document.encoded())
    }

    func testSharedLinkedPartInspectorCanApplyPreset() async throws {
        let session = EditorSession()
        _ = try await session.open(data: makeDocument().encoded())
        let selected = try await session.selectComponents(["first-link", "second-link"])
        XCTAssertNil(selected.selectedPart)
        XCTAssertEqual(selected.selectedLinkedComponentPart?.id, "a")

        let edited = try await session.setPartCutRotationPreset(
            .positiveQuarterTurn, partID: "a", target: CanvasAdjustmentTarget(snapshot: selected))
        XCTAssertEqual(edited.selectedLinkedComponentPart?.cutRotation, 0.5)
        XCTAssertEqual(edited.selectedComponentIDs, selected.selectedComponentIDs)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), selected.document.encoded())
    }

    func testImportedModelOffersZeroRotationAndPreservesExactUndo() async throws {
        let source = try makeDocument()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let selected = try await session.selectPart("imported")
        let target = CanvasAdjustmentTarget(snapshot: selected)
        do {
            _ = try await session.setPartCutRotationPreset(.positiveQuarterTurn, partID: "imported", target: target)
            XCTFail("The imported-model inspector only offers the zero reset")
        } catch {
            XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment)
        }
        let reset = try await session.setPartCutRotationPreset(.zero, partID: "imported", target: target)
        let expected = try source.applying(.setPartCutRotation(id: "imported", rotation: 0))
        XCTAssertEqual(reset.selectedPart?.cutRotation, 0)
        XCTAssertEqual(reset.document.encoded(), expected.encoded())
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        XCTAssertFalse(undone.canUndo)
    }

    func testPresetRejectsUnselectedPartAndStaleSelectionABA() async throws {
        let source = try makeDocument()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let selected = try await session.selectPart("a")
        let captured = CanvasAdjustmentTarget(snapshot: selected)
        do {
            _ = try await session.setPartCutRotationPreset(.zero, partID: "b", target: captured)
            XCTFail("A fresh target must still require its exact selected part")
        } catch {
            // The current selection does not authorize the requested part.
        }

        _ = try await session.selectPart("b")
        _ = try await session.selectPart("a")
        do {
            _ = try await session.setPartCutRotationPreset(.zero, partID: "a", target: captured)
            XCTFail("Returning to a part must not revive a captured action")
        } catch {
            XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment)
        }
        let profile = try await session.selectPart("profile")
        do {
            _ = try await session.setPartCutRotationPreset(
                .zero, partID: "profile", target: CanvasAdjustmentTarget(snapshot: profile))
            XCTFail("The preset requires a Model part")
        } catch {
            // A selected Cut Face part cannot use the preset.
        }

        let unchanged = try await session.undo()
        XCTAssertEqual(unchanged.document.encoded(), source.encoded())
        XCTAssertFalse(unchanged.canUndo)
        XCTAssertFalse(unchanged.canRedo)
    }
}
