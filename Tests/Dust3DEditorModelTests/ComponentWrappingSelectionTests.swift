import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ComponentWrappingSelectionTests: XCTestCase {
    func testMixedInactiveAndUnknownGroupsUseOneUndoAndCapturedSelection() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='a' wrap='Cloth'/><component id='b' wrap='Skin'/><component id='c' wrap='Future'/><component id='d'/></components></canvas>"
                    .utf8))
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let selected = try await session.selectComponents(["a", "b", "c", "d"])
        let target = ComponentWrappingSelectionTarget(snapshot: selected)
        XCTAssertTrue(target.isCurrent(in: selected))
        let presentation = ComponentWrappingSelectionPresentation(snapshot: selected)
        XCTAssertTrue(presentation.showsClothFields)
        XCTAssertEqual(presentation.mode, .mixed)
        let updated = try await session.editSelectedComponentWrapping(.scalar(.drape, 0.3), target: target)
        XCTAssertTrue(updated.componentTree.rows.allSatisfy { $0.component.wrapping.scalarValue(.drape) == 0.3 })
        XCTAssertNotEqual(updated.previewIdentity.geometry, selected.previewIdentity.geometry)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        XCTAssertFalse(undone.canUndo)
        XCTAssertFalse(target.isCurrent(in: undone))
    }
    func testSelectionAndConstraintAwayAndBackRejectRetainedTarget() throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='a'/><component id='b'/></components></canvas>"
                    .utf8))
        var state = try EditorState(document: source)
        try state.selectComponents(["a", "b"])
        let target = ComponentWrappingSelectionTarget(snapshot: state.snapshot)
        try state.selectComponents(["a"])
        try state.selectComponents(["a", "b"])
        XCTAssertThrowsError(try state.editSelectedComponentWrapping(.mode(.cloth), target: target))
        XCTAssertEqual(state.snapshot.document.encoded(), source.encoded())
    }
    func testConstraintCancellationAndUnavailableSelectionNeverPublish() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts><part id='p'/></parts><components><component id='a'/><component id='b' wrap='Future'/><component id='leaf' linkDataType='partId' linkData='p'/></components></canvas>"
                    .utf8))
        let session = EditorSession()
        let initial = try await session.open(data: source.encoded())
        XCTAssertFalse(ComponentWrappingSelectionTarget(snapshot: initial).isCurrent(in: initial))
        let selected = try await session.selectComponents(["a", "b"])
        let target = ComponentWrappingSelectionTarget(snapshot: selected)
        _ = try await session.setLock(.x, isLocked: true)
        let unlocked = try await session.setLock(.x, isLocked: false)
        XCTAssertFalse(target.isCurrent(in: unlocked))
        let fresh = ComponentWrappingSelectionTarget(snapshot: unlocked)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.editSelectedComponentWrapping(.surfacePattern(.spots), target: fresh)
        }
        do {
            _ = try await task.value
            XCTFail("cancelled")
        } catch { XCTAssertTrue(error is CancellationError) }
        let unchanged = try await session.setLock(.x, isLocked: false)
        XCTAssertEqual(unchanged.document.encoded(), source.encoded())
        XCTAssertFalse(unchanged.canUndo)
        let mixedLinked = try await session.selectComponents(["a", "leaf"])
        XCTAssertFalse(ComponentWrappingSelectionTarget(snapshot: mixedLinked).isCurrent(in: mixedLinked))
        XCTAssertFalse(ComponentWrappingSelectionPresentation(snapshot: mixedLinked).isAvailable)
    }
    func testUniformUnsupportedAndMixedValuesAreInformationalOnly() throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='a' wrap='Future' wrapOffset='opaque'/><component id='b' wrap='Future' wrapOffset='other'/></components></canvas>"
                    .utf8))
        var state = try EditorState(document: source)
        try state.selectComponents(["a", "b"])
        let presentation = ComponentWrappingSelectionPresentation(snapshot: state.snapshot)
        XCTAssertEqual(presentation.mode, .unsupported)
        XCTAssertEqual(presentation.scalar(.offset), .unsupported)
        XCTAssertEqual(presentation.pattern, .uniform(.none))
        XCTAssertEqual(presentation.ink, .uniform(.unset))
        XCTAssertEqual(presentation.surfaceScalar(.wrinkles), .uniform(0))
        XCTAssertEqual(presentation.keepChildren, .unsupported)
        XCTAssertEqual(presentation.faces, .unsupported)
        XCTAssertFalse(presentation.showsClothFields)
        XCTAssertEqual(state.snapshot.document.encoded(), source.encoded())
    }

    func testDanglingAliasSelectionCannotAcquireWrappingTarget() throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='cafe&#769;' wrap='Cloth'/></components></canvas>"
                    .utf8))
        var state = try EditorState(document: source)
        try state.selectComponents(["caf\u{e9}"])
        let target = ComponentWrappingSelectionTarget(snapshot: state.snapshot)
        XCTAssertFalse(target.isCurrent(in: state.snapshot))
        XCTAssertFalse(ComponentWrappingSelectionPresentation(snapshot: state.snapshot).isAvailable)
        XCTAssertThrowsError(try state.editSelectedComponentWrapping(.mode(.skin), target: target))
        XCTAssertEqual(state.snapshot.document.encoded(), source.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }

}
