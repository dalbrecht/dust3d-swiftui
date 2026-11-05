import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ComponentSurfaceSessionTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='g' wrap='Cloth'/><component id='other' wrap='Skin'/></components></canvas>"
                    .utf8))
    }
    func testTypedEditsUseCapturedGroupAndOneUndoWithoutChangingGeometryIdentity() async throws {
        let document = try source()
        let session = EditorSession()
        _ = try await session.open(data: document.encoded())
        var snapshot = try await session.selectComponent("g")
        for edit in [
            ComponentSurfaceEdit.pattern(.spots), .scalar(.wrinkles, 1), .ink(.init(red: 2, green: 3, blue: 4)),
            .ink(nil),
        ] {
            let before = snapshot
            snapshot = try await session.editComponentSurface(edit, target: .init(snapshot: snapshot))
            XCTAssertEqual(snapshot.selectedComponentID, "g")
            XCTAssertEqual(snapshot.previewIdentity.geometry, before.previewIdentity.geometry)
            XCTAssertNotEqual(snapshot.previewIdentity.materials, before.previewIdentity.materials)
            let undone = try await session.undo()
            XCTAssertEqual(undone.document.encoded(), before.document.encoded())
            snapshot = try await session.redo()
        }
    }
    func testSelectionLocksUndoReplacementAndOtherWindowRejectCapturedTarget() async throws {
        let document = try source()
        let session = EditorSession()
        _ = try await session.open(data: document.encoded())
        let first = try await session.selectComponent("g")
        let target = ComponentSurfaceTarget(snapshot: first)
        _ = try await session.selectComponent("other")
        var current = try await session.selectComponent("g")
        XCTAssertFalse(target.isCurrent(in: current))
        do {
            _ = try await session.editComponentSurface(.pattern(.spots), target: target)
            XCTFail("stale")
        } catch { XCTAssertEqual(error as? ComponentSurfaceError, .staleTarget) }
        let locks = ComponentSurfaceTarget(snapshot: current)
        _ = try await session.setLock(.x, isLocked: true)
        current = try await session.setLock(.x, isLocked: false)
        XCTAssertFalse(locks.isCurrent(in: current))
        let fresh = ComponentSurfaceTarget(snapshot: current)
        _ = try await session.editComponentSurface(.pattern(.spots), target: fresh)
        current = try await session.undo()
        XCTAssertFalse(fresh.isCurrent(in: current))
        _ = try await session.open(data: document.encoded())
        current = try await session.selectComponent("g")
        XCTAssertFalse(fresh.isCurrent(in: current))
        let other = EditorSession()
        _ = try await other.open(data: document.encoded())
        let independent = try await other.selectComponent("g")
        XCTAssertFalse(ComponentSurfaceTarget(snapshot: current).isCurrent(in: independent))
    }
    func testCancelledEditAndUnavailableTargetNeverPublish() async throws {
        let session = EditorSession()
        let document = try source()
        let initial = try await session.open(data: document.encoded())
        XCTAssertFalse(ComponentSurfaceTarget(snapshot: initial).isCurrent(in: initial))
        let selected = try await session.selectComponent("g")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.editComponentSurface(.pattern(.spots), target: .init(snapshot: selected))
        }
        do {
            _ = try await task.value
            XCTFail("cancelled")
        } catch { XCTAssertTrue(error is CancellationError) }
        let unchanged = try await session.setLock(.x, isLocked: false)
        XCTAssertEqual(unchanged.document.encoded(), document.encoded())
        XCTAssertFalse(unchanged.canUndo)
    }
    func testInactiveOpaqueAndLinkedSelectionsCannotAdmitAnActiveFinishTarget() throws {
        for attributes in ["", "wrap='future'"] {
            let document = try Dust3DDocument(
                snapshotXML: Data(
                    "<canvas><nodes/><parts><part id='p'/></parts><components><component id='g' \(attributes)/><component id='c' linkDataType='partId' linkData='p'/></components></canvas>"
                        .utf8))
            var state = try EditorState(document: document)
            for id in ["g", "c"] {
                try state.selectComponent(id)
                let target = ComponentSurfaceTarget(snapshot: state.snapshot)
                XCTAssertFalse(target.isCurrent(in: state.snapshot))
                XCTAssertThrowsError(try state.editComponentSurface(.pattern(.spots), target: target)) {
                    XCTAssertEqual($0 as? ComponentSurfaceError, .staleTarget)
                }
            }
        }
    }

}
