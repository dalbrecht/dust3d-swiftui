import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ComponentPartRoleSessionTests: XCTestCase {
    private func document(_ role: String = "", grouped: Bool = false) throws -> Dust3DDocument {
        let children =
            "<component id='a' linkDataType='partId' linkData='p'/><component id='b' linkDataType='partId' linkData='q'/>"
        return try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts><part id='p' locked='true' \(role)/><part id='q' disabled='true' visible='false' \(role)/></parts><components>\(grouped ? "<component id='g'>" + children + "<component id='sibling'/></component>" : children)</components></canvas>"
                    .utf8))
    }

    func testSessionAllocatesGroupSelectsRevealsAndCreatesOneUndo() async throws {
        let source = try document()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let selected = try await session.selectComponents(["a", "b"])
        let result = try await session.setSelectedComponentPartRole(.stitchingLine, target: .init(snapshot: selected))
        let group = try XCTUnwrap(result.selectedComponent)
        XCTAssertTrue(group.isGroup)
        XCTAssertNotNil(UUID(uuidString: String(group.id.dropFirst().dropLast())))
        XCTAssertEqual(group.childIDs, ["a", "b"])
        XCTAssertEqual(result.componentRevealHint?.componentID, group.id)
        XCTAssertTrue(result.parts.allSatisfy { $0.target == .stitchingLine })
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        XCTAssertFalse(undone.canUndo)
    }

    func testSameRoleReuseRevealsGroupWithoutHistoryAndRejectsSelectionAwayBack() async throws {
        let session = EditorSession()
        let source = try document("target='StitchingLoop'", grouped: true)
        _ = try await session.open(data: source.encoded())
        let first = try await session.selectComponents(["a", "b"])
        let target = ComponentPartRoleTarget(snapshot: first)
        _ = try await session.selectComponent("a")
        let selected = try await session.selectComponents(["a", "b"])
        do {
            _ = try await session.setSelectedComponentPartRole(.stitchingLoop, target: target)
            XCTFail("stale")
        } catch { XCTAssertEqual(error as? ComponentPartRoleError, .staleContext) }
        let result = try await session.setSelectedComponentPartRole(.stitchingLoop, target: .init(snapshot: selected))
        XCTAssertEqual(result.selectedComponentID, "g")
        XCTAssertEqual(result.componentRevealHint?.componentID, "g")
        XCTAssertEqual(result.document.encoded(), source.encoded())
        XCTAssertEqual(result.documentRevision, selected.documentRevision)
        XCTAssertFalse(result.canUndo)
    }
    func testLockAwayBackUndoAndDocumentReplacementInvalidateCapturedTargets() async throws {
        let source = try document()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let selected = try await session.selectComponents(["a", "b"])
        let target = ComponentPartRoleTarget(snapshot: selected)
        _ = try await session.setLock(.x, isLocked: true)
        let unlocked = try await session.setLock(.x, isLocked: false)
        XCTAssertFalse(target.isCurrent(in: unlocked))
        do {
            _ = try await session.setSelectedComponentPartRole(.cutFace, target: target)
            XCTFail("stale locks")
        } catch { XCTAssertEqual(error as? ComponentPartRoleError, .staleContext) }
        let fresh = ComponentPartRoleTarget(snapshot: unlocked)
        _ = try await session.setSelectedComponentPartRole(.cutFace, target: fresh)
        let undone = try await session.undo()
        XCTAssertFalse(fresh.isCurrent(in: undone))
        _ = try await session.open(data: source.encoded())
        let replacement = try await session.selectComponents(["a", "b"])
        XCTAssertFalse(fresh.isCurrent(in: replacement))
        let other = EditorSession()
        _ = try await other.open(data: source.encoded())
        let independentlySelected = try await other.selectComponents(["a", "b"])
        XCTAssertFalse(ComponentPartRoleTarget(snapshot: replacement).isCurrent(in: independentlySelected))
    }

    func testAlreadyCancelledRoleTaskCannotPublishAndStateRejectsStaleBeforeMutation() async throws {
        let source = try document()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let selected = try await session.selectComponents(["a", "b"])
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.setSelectedComponentPartRole(.stitchingLoop, target: .init(snapshot: selected))
        }
        do {
            _ = try await operation.value
            XCTFail("cancelled")
        } catch { XCTAssertTrue(error is CancellationError) }
        let unchanged = try await session.setLock(.x, isLocked: false)
        XCTAssertEqual(unchanged.document.encoded(), source.encoded())
        XCTAssertFalse(unchanged.canUndo)
        var state = try EditorState(document: source)
        try state.selectComponents(["a", "b"])
        let stale = ComponentPartRoleTarget(snapshot: state.snapshot)
        try state.selectComponent("a")
        XCTAssertThrowsError(try state.setSelectedComponentPartRole(.cutFace, target: stale, newGroupID: nil)) {
            XCTAssertEqual($0 as? ComponentPartRoleError, .staleContext)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), source.encoded())
    }

}
