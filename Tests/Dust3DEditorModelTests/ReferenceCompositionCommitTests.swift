import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ReferenceCompositionCommitTests: XCTestCase {
    private let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 1])
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 1, y: 2, z: 3), radius: 0.1))
    }

    func testImageAndOriginCommitAreOneLosslessUndoStepWithNativeLocks() throws {
        let original = try document()
        var state = try EditorState(document: original)
        state.setLock(.x, isLocked: true)
        let target = ReferenceCompositionTarget(snapshot: state.snapshot)
        try state.select("a")
        try state.applyReferenceComposition(png: png, origin: .init(x: 2, y: 3, z: 4), target: target)
        let result = state.snapshot
        XCTAssertEqual(result.document.referenceImagePNG, png)
        XCTAssertEqual(result.origin, .init(x: 0.5, y: 3, z: 4))
        XCTAssertEqual(try result.document.node(id: "a"), try original.node(id: "a"))
        XCTAssertEqual(result.selectedID, "a")
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
        try state.redo()
        XCTAssertEqual(state.snapshot.document.encoded(), result.document.encoded())
    }

    func testStaleDocumentRevisionIdentityAndLockCyclesRejectAtomically() throws {
        let original = try document()
        var state = try EditorState(document: original)
        let target = ReferenceCompositionTarget(snapshot: state.snapshot)
        try state.apply([.setOrigin(.init(x: 1, y: 1, z: 1))])
        try state.undo()
        XCTAssertThrowsError(try state.applyReferenceComposition(png: png, origin: nil, target: target)) {
            XCTAssertEqual($0 as? EditorError, .staleReferenceComposition)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertTrue(state.snapshot.canRedo)
        state = try EditorState(document: original)
        XCTAssertThrowsError(try state.applyReferenceComposition(png: png, origin: nil, target: target))
        let current = ReferenceCompositionTarget(snapshot: state.snapshot)
        state.setLock(.y, isLocked: true)
        state.setLock(.y, isLocked: false)
        XCTAssertThrowsError(try state.applyReferenceComposition(png: png, origin: nil, target: current))
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
    }

    func testInvalidBatchNeverCommitsImageAndNoopPreservesRedo() throws {
        var state = try EditorState(document: document())
        let original = state.snapshot.document.encoded()
        let target = ReferenceCompositionTarget(snapshot: state.snapshot)
        XCTAssertThrowsError(
            try state.applyReferenceComposition(png: png, origin: .init(x: .nan, y: 0, z: 0), target: target))
        XCTAssertThrowsError(try state.applyReferenceComposition(png: Data(), origin: nil, target: target))
        XCTAssertEqual(state.snapshot.document.encoded(), original)
        try state.applyReferenceComposition(png: png, origin: nil, target: target)
        XCTAssertEqual(state.snapshot.origin, .init(x: 0.5, y: 0.5, z: 0.5))
        let withImage = state.snapshot.document.encoded()
        try state.apply([.setOrigin(.init(x: 2, y: 2, z: 2))])
        try state.undo()
        try state.applyReferenceComposition(png: png, origin: nil, target: .init(snapshot: state.snapshot))
        XCTAssertEqual(state.snapshot.document.encoded(), withImage)
        XCTAssertTrue(state.snapshot.canRedo)
    }

    @MainActor func testSessionRejectsReplacedDocumentAndCommitsToItsOwnWindowOnly() async throws {
        let source = try document()
        let first = EditorSession()
        let second = EditorSession()
        let snapshot = try await first.open(data: source.encoded())
        let target = ReferenceCompositionTarget(snapshot: snapshot)
        do {
            _ = try await second.applyReferenceComposition(png: png, origin: nil, target: target)
            XCTFail("Unloaded session must reject")
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
        _ = try await second.open(data: source.encoded())
        do {
            _ = try await second.applyReferenceComposition(png: png, origin: nil, target: target)
            XCTFail("Another window must reject")
        } catch { XCTAssertEqual(error as? EditorError, .staleReferenceComposition) }
        let result = try await first.applyReferenceComposition(png: png, origin: nil, target: target)
        XCTAssertEqual(result.document.referenceImagePNG, png)
        let restored = try await first.undo()
        XCTAssertEqual(restored.document.encoded(), source.encoded())
        _ = try await first.open(data: source.encoded())
        do {
            _ = try await first.applyReferenceComposition(png: png, origin: nil, target: target)
            XCTFail("Reopened identical document must reject old draft")
        } catch { XCTAssertEqual(error as? EditorError, .staleReferenceComposition) }
    }
}
