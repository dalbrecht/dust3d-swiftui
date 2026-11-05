import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ComponentUngroupSelectionTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes><node id='n' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='p' locked='true' visible='false' disabled='true'/></parts><components><component id='a' linkDataType='future' linkData='opaque'><component id='keep'><component id='b' linkDataType='partId' linkData='p'><component id='child'/></component></component></component><component id='leaf' linkDataType='partId' linkData='p'/></components></canvas>"
                    .utf8))
    }
    func testOneContextualLoadedWrapperUsesSameTransactionWithoutDummySiblingAndRetainsEarlierSelection() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectComponents(["leaf"])
        let target = ComponentUngroupTarget(snapshot: selected, componentIDs: ["a"])
        XCTAssertEqual(target.wrapperCount, 1)
        let after = try await session.ungroupComponents(target: target)
        XCTAssertEqual(after.componentTree.rows.map(\.id), ["keep", "b", "child", "leaf"])
        XCTAssertEqual(after.selectedComponentIDs, ["leaf"])
        XCTAssertEqual(after.selectionRevision, selected.selectionRevision)
        XCTAssertEqual(after.nodes, selected.nodes)
        XCTAssertEqual(after.parts, selected.parts)
        let undo = try await session.undo()
        XCTAssertTrue(undo.document.hasSameEditingState(as: original))
        XCTAssertFalse(undo.canUndo)
    }
    func testEveryExplicitNestedWrapperFlattensAndTransientSelectionPrunesOnlyOnce() async throws {
        let session = EditorSession()
        let original = try source()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectComponents(["a", "b", "leaf"])
        let target = ComponentUngroupTarget(snapshot: selected)
        XCTAssertEqual(target.wrapperCount, 2)
        let after = try await session.ungroupComponents(target: target)
        XCTAssertEqual(after.componentTree.rows.map(\.id), ["keep", "child", "leaf"])
        XCTAssertEqual(after.selectedComponentIDs, ["leaf"])
        XCTAssertEqual(after.selectionRevision, selected.selectionRevision + 1)
        let undo = try await session.undo()
        XCTAssertEqual(undo.document.encoded(), original.encoded())
        XCTAssertEqual(undo.selectedComponentIDs, ["leaf"])
        do {
            _ = try await session.ungroupComponents(target: target)
            XCTFail("Undo is a new document epoch")
        } catch { XCTAssertEqual(error as? ComponentUngroupSelectionError, .staleTarget) }
    }
    func testSelectionConstraintLoadAndWindowEpochsRejectRetainedIntent() async throws {
        for change in 0..<4 {
            let session = EditorSession()
            let original = try source()
            _ = try await session.open(data: original.encoded())
            let initial = try await session.selectComponents(["a"])
            let target = ComponentUngroupTarget(snapshot: initial)
            switch change {
            case 0:
                _ = try await session.selectComponents(["leaf"])
                _ = try await session.selectComponents(["a"])
            case 1:
                _ = try await session.setLock(.x, isLocked: true)
                _ = try await session.setLock(.x, isLocked: false)
            case 2: _ = try await session.open(data: original.encoded())
            default:
                let other = EditorSession()
                _ = try await other.open(data: original.encoded())
                do {
                    _ = try await other.ungroupComponents(target: target)
                    XCTFail("Other window")
                } catch { XCTAssertEqual(error as? ComponentUngroupSelectionError, .staleTarget) }
                continue
            }
            do {
                _ = try await session.ungroupComponents(target: target)
                XCTFail("Stale intent")
            } catch { XCTAssertEqual(error as? ComponentUngroupSelectionError, .staleTarget) }
        }
    }
    func testByteDistinctSelectionChangesInvalidateRetainedUngroupIncludingReturnToOriginal() throws {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><components><component id='cafe&#769;'><component id='child'/></component></components></canvas>"
                    .utf8))
        for returnToOriginal in [false, true] {
            var state = try EditorState(document: original)
            try state.selectComponents(["cafe\u{301}"])
            let before = state.snapshot
            let target = ComponentUngroupTarget(snapshot: before)
            XCTAssertEqual(target.wrapperCount, 1)
            try state.selectComponents(["caf\u{e9}"])
            XCTAssertEqual(state.snapshot.selectionRevision, before.selectionRevision + 1)
            XCTAssertEqual(Set(state.snapshot.selectedComponentIDs.map { Data($0.utf8) }), [Data("caf\u{e9}".utf8)])
            XCTAssertEqual(ComponentUngroupTarget(snapshot: state.snapshot).wrapperCount, 0)
            if returnToOriginal {
                try state.selectComponent("cafe\u{301}")
                XCTAssertEqual(state.snapshot.selectionRevision, before.selectionRevision + 2)
            }
            XCTAssertFalse(target.isCurrent(in: state.snapshot))
            XCTAssertThrowsError(try state.ungroupComponents(target: target)) {
                XCTAssertEqual($0 as? ComponentUngroupSelectionError, .staleTarget)
            }
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertEqual(state.snapshot.documentRevision, before.documentRevision)
            XCTAssertEqual(state.snapshot.previewIdentity, before.previewIdentity)
            XCTAssertFalse(state.snapshot.canUndo)
            if returnToOriginal {
                try state.ungroupComponents(target: .init(snapshot: state.snapshot))
                XCTAssertEqual(state.snapshot.componentTree.rows.map(\.id), ["child"])
                try state.undo()
                XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            }
        }
    }

    func testUnavailableExactAliasesCancellationAndContextErrorsNeverPublishOrAcquireLaterTarget() async throws {
        let original = try source()
        let session = EditorSession()
        let empty = try await session.open(data: original.encoded())
        let unavailable = ComponentUngroupTarget(snapshot: empty)
        let selected = try await session.selectComponents(["a"])
        XCTAssertFalse(unavailable.isCurrent(in: selected))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.ungroupComponents(target: .init(snapshot: selected))
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled")
        } catch { XCTAssertTrue(error is CancellationError) }
        let current = try await session.selectComponents(["a"])
        XCTAssertEqual(current.document.encoded(), original.encoded())
        XCTAssertFalse(current.canUndo)
        let contextDoc = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><components><component id='g' xml:lang='fr'><component id='c'/></component></components></canvas>"
                    .utf8))
        let ctx = try await session.open(data: contextDoc.encoded())
        do {
            _ = try await session.ungroupComponents(target: .init(snapshot: ctx, componentIDs: ["g"]))
            XCTFail("Changed XML language")
        } catch {
            XCTAssertEqual(error as? ComponentUngroupError, .inheritedContext(componentID: "g", attribute: "xml:lang"))
        }
        let after = try await session.selectComponent(nil)
        XCTAssertEqual(after.document.encoded(), contextDoc.encoded())
        XCTAssertFalse(after.canUndo)
        let aliasDoc = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><components><component id='cafe&#769;'><component id='c'/></component></components></canvas>"
                    .utf8))
        var state = try EditorState(document: aliasDoc)
        try state.selectComponents(["caf\u{e9}"])
        XCTAssertEqual(ComponentUngroupTarget(snapshot: state.snapshot).wrapperCount, 0)
        XCTAssertEqual(
            ComponentUngroupTarget(snapshot: state.snapshot, componentIDs: ["cafe\u{301}", "caf\u{e9}"]).wrapperCount, 0
        )
    }
}
