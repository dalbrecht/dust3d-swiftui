import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class ReferenceColorEditingTests: XCTestCase {
    private func document(flags: String = "", ambiguous: Bool = false) throws -> Dust3DDocument {
        var value = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='.1' y='.1' z='.1' radius='.1'/><node id='b' partId='q' x='.6' y='.1' z='.6' radius='.1'/></nodes><edges><edge id='e' from='a' to='b' partId='q'/></edges><parts><part id='p'/><part id='q' \(flags)/></parts><components><component id='cp' linkDataType='partId' linkData='p' color='#123456' colorImageId='retained'/><component id='cq' linkDataType='partId' linkData='q'/>\(ambiguous ? "<component id='dup' linkDataType='partId' linkData='q'/>" : "")</components></canvas>
                """.utf8))
        value = try value.applying(.setReferenceImagePNG(png))
        return value
    }
    private var png: Data {
        Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")
            ?? Data()
    }
    private func input(_ snapshot: EditorSnapshot) throws -> (ReferenceColorRaster, ReferenceColorSamplingLayout) {
        (
            try ReferenceColorRaster(width: 1, height: 1, rowStride: 4, pixels: Data([11, 22, 33, 0])),
            try ReferenceColorSamplingLayout(
                referenceSize: .init(width: 1, height: 1),
                projection: .init(
                    bounds: .init(nodes: snapshot.nodes, referenceImageAspectRatio: 1), plane: .front, width: 400,
                    height: 400))
        )
    }
    func testAutoColorIsAtomicOneUndoKeepsSelectionAndImageAndNoopKeepsPreview() throws {
        let source = try document()
        var state = try EditorState(document: source)
        try state.selectGraph(nodes: ["a"], edges: ["e"])
        let target = ReferenceColorTarget(snapshot: state.snapshot)
        let (raster, layout) = try input(state.snapshot)
        let plan = try state.autoColorSelectedParts(raster: raster, layout: layout, referencePNG: png, target: target)
        XCTAssertEqual(plan.updates.count, 2)
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["e"])
        XCTAssertEqual(state.snapshot.selectedIDs, ["a"])
        XCTAssertEqual(state.snapshot.document.referenceImagePNG, png)
        let bytes = state.snapshot.document.encoded()
        let identity = state.snapshot.previewIdentity
        _ = try state.autoColorSelectedParts(
            raster: raster, layout: layout, referencePNG: png, target: .init(snapshot: state.snapshot))
        XCTAssertEqual(state.snapshot.document.encoded(), bytes)
        XCTAssertEqual(state.snapshot.previewIdentity, identity)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), source.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }
    func testClearNeedsNoImageAndPreservesOtherMaterialFieldsAndExactUndo() throws {
        let source = try document().applying(.setReferenceImagePNG(nil))
        var state = try EditorState(document: source)
        try state.selectGraph(nodes: ["a"], edges: ["e"])
        _ = try state.clearSelectedPartColors(target: .init(snapshot: state.snapshot))
        XCTAssertFalse(String(decoding: state.snapshot.document.modelXML, as: UTF8.self).contains("#123456"))
        XCTAssertTrue(
            String(decoding: state.snapshot.document.modelXML, as: UTF8.self).contains("colorImageId=\"retained\"")
                || String(decoding: state.snapshot.document.modelXML, as: UTF8.self).contains("colorImageId='retained'")
        )
        let identity = state.snapshot.previewIdentity
        _ = try state.clearSelectedPartColors()
        XCTAssertEqual(state.snapshot.previewIdentity, identity)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), source.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }
    func testStaleSelectionConstraintSourceReplacementAndOwnershipFailureNeverPartiallyCommit() throws {
        var state = try EditorState(document: document())
        try state.select("a")
        let target = ReferenceColorTarget(snapshot: state.snapshot)
        let clearTarget = CanvasAdjustmentTarget(snapshot: state.snapshot)
        let (raster, layout) = try input(state.snapshot)
        state.setLock(.x, isLocked: true)
        XCTAssertThrowsError(try state.clearSelectedPartColors(target: clearTarget)) {
            XCTAssertEqual($0 as? EditorError, .staleReferenceColor)
        }
        XCTAssertThrowsError(
            try state.autoColorSelectedParts(raster: raster, layout: layout, referencePNG: png, target: target))
        let current = ReferenceColorTarget(snapshot: state.snapshot)
        XCTAssertThrowsError(
            try state.autoColorSelectedParts(raster: raster, layout: layout, referencePNG: Data(), target: current))
        var ambiguous = try EditorState(document: document(ambiguous: true))
        try ambiguous.selectGraph(nodes: ["a"], edges: ["e"])
        let before = ambiguous.snapshot.document.encoded()
        XCTAssertThrowsError(
            try ambiguous.autoColorSelectedParts(
                raster: raster, layout: layout, referencePNG: png, target: .init(snapshot: ambiguous.snapshot)))
        XCTAssertEqual(ambiguous.snapshot.document.encoded(), before)
        XCTAssertFalse(ambiguous.snapshot.canUndo)
        var readonly = try EditorState(document: document(flags: "locked='true'"))
        try readonly.selectGraph(nodes: ["a"], edges: ["e"])
        let plan = try readonly.autoColorSelectedParts(
            raster: raster, layout: layout, referencePNG: png, target: .init(snapshot: readonly.snapshot))
        XCTAssertEqual(plan.skippedReadOnlyObjects, 1)
        XCTAssertEqual(plan.updates.count, 1)
    }
    func testActorReportsOnlyChangedComponentsAndAllNoopKeepsHistory() async throws {
        let color = DocumentColor(red: 11, green: 22, blue: 33)
        let source = try document().applying(.setComponentColor(id: "cp", color: color))
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let selected = try await session.selectGraph(nodes: ["a"], edges: ["e"])
        let (raster, layout) = try input(selected)
        let receipt = try await session.autoColorSelectedParts(
            raster: raster, layout: layout,
            referencePNG: png, target: .init(snapshot: selected))
        XCTAssertEqual(receipt.changedComponentCount, 1)
        XCTAssertTrue(receipt.didChange)
        let unchanged = try await session.autoColorSelectedParts(
            raster: raster, layout: layout,
            referencePNG: png, target: .init(snapshot: receipt.snapshot))
        XCTAssertEqual(unchanged.changedComponentCount, 0)
        XCTAssertFalse(unchanged.didChange)
        XCTAssertEqual(unchanged.snapshot.previewIdentity, receipt.snapshot.previewIdentity)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        XCTAssertFalse(undone.canUndo)
    }
    func testActorRejectsEdgeOnlyIntentStaleWindowAndPreCancelledWork() async throws {
        let source = try document()
        let session = EditorSession()
        let initial = try await session.open(data: source.encoded())
        let (raster, layout) = try input(initial)
        let edgeOnly = try await session.selectGraph(nodes: [], edges: ["e"])
        do {
            _ = try await session.autoColorSelectedParts(
                raster: raster, layout: layout, referencePNG: png,
                target: .init(snapshot: edgeOnly))
            XCTFail("Expected explicit-node admission")
        } catch { XCTAssertEqual(error as? EditorError, .invalidReferenceColorSelection) }
        do {
            _ = try await session.clearSelectedPartColors(target: .init(snapshot: edgeOnly))
            XCTFail("Expected explicit-node admission")
        } catch { XCTAssertEqual(error as? EditorError, .invalidReferenceColorSelection) }
        let selected = try await session.select("a")
        let other = EditorSession()
        _ = try await other.open(data: source.encoded())
        _ = try await other.select("a")
        do {
            _ = try await other.autoColorSelectedParts(
                raster: raster, layout: layout, referencePNG: png,
                target: .init(snapshot: selected))
            XCTFail("Expected foreign-window rejection")
        } catch { XCTAssertEqual(error as? EditorError, .staleReferenceColor) }
        let sourcePNG = png
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.autoColorSelectedParts(
                raster: raster, layout: layout, referencePNG: sourcePNG,
                target: .init(snapshot: selected))
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let unchanged = try await session.select("a")
        XCTAssertEqual(unchanged.document.encoded(), source.encoded())
        XCTAssertFalse(unchanged.canUndo)
    }

}
