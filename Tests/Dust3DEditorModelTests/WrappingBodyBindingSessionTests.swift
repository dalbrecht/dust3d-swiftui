import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@MainActor final class WrappingBodyBindingSessionTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts/><components><component id='ancestor'><component id='owner' wrap='Cloth' wrapBindTo='missing'><component id='child'/></component></component><component id='body'/></components></canvas>
                """.utf8))
    }
    func testCapturedBindingChangesBothPreviewInputsKeepsSelectionAndUsesOneUndo() async throws {
        let document = try source()
        let session = EditorSession()
        _ = try await session.open(data: document.encoded())
        let before = try await session.selectComponent("owner")
        let after = try await session.editComponentWrapBinding(.group("body"), target: .init(snapshot: before))
        XCTAssertEqual(after.selectedComponentID, "owner")
        XCTAssertEqual(after.selectedComponent?.wrapping.binding, .stored("body"))
        XCTAssertNotEqual(after.previewIdentity.geometry, before.previewIdentity.geometry)
        XCTAssertNotEqual(after.previewIdentity.materials, before.previewIdentity.materials)
        let undo = try await session.undo()
        XCTAssertEqual(undo.document.encoded(), document.encoded())
        XCTAssertFalse(undo.canUndo)
        let redo = try await session.redo()
        XCTAssertEqual(redo.document.encoded(), after.document.encoded())
        let current = ComponentWrapBindingTarget(snapshot: redo)
        let noop = try await session.editComponentWrapBinding(.group("body"), target: current)
        XCTAssertEqual(noop.previewIdentity, redo.previewIdentity)
    }
    func testSelectionConstraintsReplacementAndOtherWindowsRejectRetainedTargetWithoutRetargeting() async throws {
        for change in 0..<4 {
            let document = try source()
            let session = EditorSession()
            _ = try await session.open(data: document.encoded())
            let original = try await session.selectComponent("owner")
            let target = ComponentWrapBindingTarget(snapshot: original)
            let destination: EditorSession
            switch change {
            case 0:
                _ = try await session.selectComponent("body")
                _ = try await session.selectComponent("owner")
                destination = session
            case 1:
                _ = try await session.setLock(.x, isLocked: true)
                _ = try await session.setLock(.x, isLocked: false)
                destination = session
            case 2:
                _ = try await session.open(data: document.encoded())
                _ = try await session.selectComponent("owner")
                destination = session
            default:
                destination = EditorSession()
                _ = try await destination.open(data: document.encoded())
                _ = try await destination.selectComponent("owner")
            }
            do {
                _ = try await destination.editComponentWrapBinding(.group("body"), target: target)
                XCTFail("A retained target must not acquire a later inspector")
            } catch { XCTAssertEqual(error as? ComponentWrapBindingError, .staleTarget) }
            let unchanged = try await destination.selectComponent("owner")
            XCTAssertEqual(unchanged.document.encoded(), document.encoded())
            XCTAssertFalse(unchanged.canUndo)
        }
    }
    func testUnavailableAndUndoneContextsStayStaleAndCancellationPublishesNothing() async throws {
        let document = try source()
        let session = EditorSession()
        _ = try await session.open(data: document.encoded())
        let unavailable = try await session.selectComponent("body")
        let invalid = ComponentWrapBindingTarget(snapshot: unavailable)
        let owner = try await session.selectComponent("owner")
        do {
            _ = try await session.editComponentWrapBinding(.ownChildren, target: invalid)
            XCTFail("An unavailable captured target stays unavailable")
        } catch { XCTAssertEqual(error as? ComponentWrapBindingError, .staleTarget) }
        let target = ComponentWrapBindingTarget(snapshot: owner)
        _ = try await session.apply([.setComponentName(id: "owner", name: "temporary")])
        let undone = try await session.undo()
        XCTAssertTrue(undone.canRedo)
        do {
            _ = try await session.editComponentWrapBinding(.ownChildren, target: target)
            XCTFail("Undo must not restore admission")
        } catch { XCTAssertEqual(error as? ComponentWrapBindingError, .staleTarget) }
        let current = try await session.selectComponent("owner")
        let cancelled = Task {
            try await session.editComponentWrapBinding(.group("body"), target: .init(snapshot: current))
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled queued edit must not publish")
        } catch { XCTAssertTrue(error is CancellationError) }
        let final = try await session.selectComponent("owner")
        XCTAssertEqual(final.document.encoded(), document.encoded())
        XCTAssertTrue(final.canRedo)
    }
}
