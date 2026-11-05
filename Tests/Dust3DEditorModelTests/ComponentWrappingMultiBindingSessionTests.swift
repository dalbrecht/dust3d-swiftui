import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@MainActor final class ComponentWrappingMultiBindingSessionTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts/><components><component id='a' wrap='Cloth' wrapBindTo='caf&#233;'/><component id='b' wrap='Future' wrapBindTo='cafe&#769;'/><component id='c' wrapBindTo=''/><component id='d'/><component id='body'/></components></canvas>
                """.utf8))
    }
    func testActualBatchActorStoresBindingAcrossAllModesWithOneUndoAndBothIdentities() async throws {
        let session = EditorSession()
        let original = try source()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectComponents(["a", "b", "c", "d"])
        let target = ComponentWrappingSelectionTarget(snapshot: selected)
        let changed = try await session.editSelectedComponentWrapping(.binding(.group("body")), target: target)
        XCTAssertEqual(changed.selectedComponentIDs, selected.selectedComponentIDs)
        XCTAssertNotEqual(changed.previewIdentity.geometry, selected.previewIdentity.geometry)
        XCTAssertNotEqual(changed.previewIdentity.materials, selected.previewIdentity.materials)
        XCTAssertEqual(ComponentWrappingSelectionPresentation(snapshot: changed).binding, .uniform(.stored("body")))
        XCTAssertEqual(
            changed.selectedComponentRows.map { $0.component.wrapping.mode },
            [.cloth, nil, ComponentWrapMode.none, ComponentWrapMode.none])
        let noop = try await session.editSelectedComponentWrapping(
            .binding(.group("body")), target: .init(snapshot: changed))
        XCTAssertEqual(noop.documentRevision, changed.documentRevision)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
        let emptyNoop = try await session.selectComponents(["c", "d"])
        let unchanged = try await session.editSelectedComponentWrapping(
            .binding(.ownChildren), target: .init(snapshot: emptyNoop))
        XCTAssertEqual(unchanged.document.encoded(), original.encoded())
        XCTAssertTrue(unchanged.canRedo)
    }
    func testMixedRawBindingValuesStayByteDistinctAndNeverBecomeImplicitReplacements() async throws {
        let session = EditorSession()
        let original = try source()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectComponents(["a", "b"])
        XCTAssertEqual(ComponentWrappingSelectionPresentation(snapshot: selected).binding, .mixed)
        let first = try await session.selectComponents(["a"])
        XCTAssertEqual(ComponentWrappingSelectionPresentation(snapshot: first).binding, .uniform(.stored("caf\u{e9}")))
        let second = try await session.selectComponents(["b"])
        XCTAssertEqual(
            ComponentWrappingSelectionPresentation(snapshot: second).binding, .uniform(.stored("cafe\u{301}")))
        let emptyAndAbsent = try await session.selectComponents(["c", "d"])
        XCTAssertEqual(ComponentWrappingSelectionPresentation(snapshot: emptyAndAbsent).binding, .mixed)
        XCTAssertEqual(emptyAndAbsent.document.encoded(), original.encoded())
        XCTAssertFalse(emptyAndAbsent.canUndo)
    }
    func testStaleTargetsAcrossABAReplacementWindowsAndInvalidUnionRejectAtomically() async throws {
        let original = try source()
        for change in 0..<4 {
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            let selected = try await session.selectComponents(["a", "b"])
            let target = ComponentWrappingSelectionTarget(snapshot: selected)
            let before: EditorSnapshot
            switch change {
            case 0:
                _ = try await session.selectComponents(["a"])
                before = try await session.selectComponents(["a", "b"])
            case 1:
                _ = try await session.setLock(.x, isLocked: true)
                before = try await session.setLock(.x, isLocked: false)
            case 2:
                _ = try await session.open(data: original.encoded())
                before = try await session.selectComponents(["a", "b"])
            default:
                let other = EditorSession()
                _ = try await other.open(data: original.encoded())
                _ = try await other.selectComponents(["a", "b"])
                do {
                    _ = try await other.editSelectedComponentWrapping(.binding(.group("body")), target: target)
                    XCTFail("Cross-window target")
                } catch { XCTAssertEqual(error as? ComponentWrappingSelectionError, .staleTarget) }
                before = selected
            }
            if change < 3 {
                do {
                    _ = try await session.editSelectedComponentWrapping(.binding(.group("body")), target: target)
                    XCTFail("Stale target")
                } catch { XCTAssertEqual(error as? ComponentWrappingSelectionError, .staleTarget) }
            }
            do {
                _ = try await session.editSelectedComponentWrapping(
                    .binding(.group("a")), target: .init(snapshot: before))
                XCTFail("Union owner target")
            } catch { XCTAssertEqual(error as? DocumentError, .invalidComponentWrapBinding) }
            let after = try await session.selectComponents(["a", "b"])
            XCTAssertEqual(after.document.encoded(), original.encoded())
            XCTAssertFalse(after.canUndo)
        }
    }
    func testCancelledBatchBindingPublishesNoHistoryOrSourceChanges() async throws {
        let session = EditorSession()
        let original = try source()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectComponents(["a", "b"])
        let target = ComponentWrappingSelectionTarget(snapshot: selected)
        let task = Task { try await session.editSelectedComponentWrapping(.binding(.group("body")), target: target) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled binding must not publish")
        } catch { XCTAssertTrue(error is CancellationError) }
        let current = try await session.selectComponents(["a", "b"])
        XCTAssertEqual(current.document.encoded(), original.encoded())
        XCTAssertEqual(current.previewIdentity, selected.previewIdentity)
        XCTAssertFalse(current.canUndo)
    }

}
