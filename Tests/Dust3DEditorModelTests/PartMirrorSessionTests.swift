import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@MainActor final class PartMirrorSessionTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes><node id='n' partId='p' x='2' y='.5' z='.5' radius='.2'/></nodes><edges/><parts><part id='p' target='Model' locked='true' visible='false' disabled='true'/><part id='q' target='CutFace' xMirrored='future'/></parts><components><component id='a' linkDataType='partId' linkData='p'/><component id='b' linkDataType='partId' linkData='p'/><component id='c' linkDataType='partId' linkData='q'/></components></canvas>"
                    .utf8))
    }
    func testSharedOwnerInspectorIgnoresLocksAndEditsWithOneUndo() async throws {
        let doc = try source()
        let session = EditorSession()
        _ = try await session.open(data: doc.encoded())
        let selected = try await session.selectComponents(["a", "b"])
        XCTAssertEqual(selected.mirrorInspectorPart?.id, "p")
        let locked = try await session.setLock(.x, isLocked: true)
        let target = PartMirrorTarget(snapshot: locked, partID: "p")
        let after = try await session.setPartXMirrored(true, target: target)
        XCTAssertEqual(after.parts.first?.xMirrored, true)
        XCTAssertEqual(after.selectedComponentIDs, ["a", "b"])
        XCTAssertEqual(try after.document.origin()?.x, 2)
        let undo = try await session.undo()
        XCTAssertEqual(undo.document.encoded(), doc.encoded())
        XCTAssertFalse(undo.canUndo)
        let mixed = try await session.selectComponents(["a", "c"])
        XCTAssertNil(mixed.mirrorInspectorPart)
        let unavailable = PartMirrorTarget(snapshot: mixed, partID: "q")
        XCTAssertFalse(unavailable.isCurrent(in: mixed))
        do {
            _ = try await session.setPartXMirrored(false, target: unavailable)
            XCTFail("An unsupported part acquired an inspector edit")
        } catch {
            XCTAssertEqual(error as? PartMirrorError, .staleTarget)
        }
    }
    func testEpochsAndUnavailableIdentityNeverRetarget() async throws {
        for change in 0..<4 {
            let doc = try source()
            let session = EditorSession()
            _ = try await session.open(data: doc.encoded())
            let initial = try await session.selectComponent("a")
            let target = PartMirrorTarget(snapshot: initial, partID: "p")
            XCTAssertTrue(target.isCurrent(in: initial))
            switch change {
            case 0:
                _ = try await session.selectComponent(nil)
                _ = try await session.selectComponent("a")
            case 1:
                _ = try await session.setLock(.x, isLocked: true)
                _ = try await session.setLock(.x, isLocked: false)
            case 2:
                _ = try await session.open(data: doc.encoded())
            default:
                _ = try await session.apply([.setPartName(id: "p", name: "changed")])
                _ = try await session.undo()
            }
            do {
                _ = try await session.setPartXMirrored(true, target: target)
                XCTFail("Retained target acquired a new epoch")
            } catch { XCTAssertEqual(error as? PartMirrorError, .staleTarget) }
        }
    }
    func testByteExactOwnershipAndUnavailableInspectorNeverNormalizeOrAcquireTarget() throws {
        let nfd = "e\u{301}"
        let nfc = "\u{e9}"
        let doc = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes><node id='n' partId='\(nfc)' x='0' y='0' z='0' radius='.1'/></nodes><edges><edge id='e' partId='\(nfd)' from='n' to='n'/></edges><parts><part id='\(nfd)' target='Model'/><part id='q' target='CutFace'/></parts><components><component id='a' linkDataType='partId' linkData='\(nfd)'/><component id='missing' linkDataType='partId' linkData='\(nfc)'/><component id='group'/></components></canvas>"
                    .utf8))
        var state = try EditorState(document: doc)
        try state.selectPart(nfd)
        XCTAssertTrue(PartMirrorTarget(snapshot: state.snapshot, partID: nfd).isCurrent(in: state.snapshot))
        let unavailable = PartMirrorTarget(snapshot: state.snapshot, partID: nfc)
        XCTAssertNil(unavailable.partID)
        XCTAssertFalse(unavailable.isCurrent(in: state.snapshot))
        try state.selectComponents(["a", "missing"])
        XCTAssertNil(state.snapshot.mirrorInspectorPart)
        try state.selectComponent("missing")
        XCTAssertNil(state.snapshot.mirrorInspectorPart)
        try state.selectComponent("group")
        XCTAssertNil(state.snapshot.mirrorInspectorPart)
        try state.selectPart("q")
        XCTAssertNil(state.snapshot.mirrorInspectorPart)
        try state.selectPart(nfd)
        XCTAssertNotNil(state.snapshot.mirrorInspectorPart)
    }
    func testFailedReplacementRejectsRetainedMirrorTarget() async throws {
        let doc = try source()
        let session = EditorSession()
        _ = try await session.open(data: doc.encoded())
        let before = try await session.selectComponent("a")
        let target = PartMirrorTarget(snapshot: before, partID: "p")
        do {
            _ = try await session.open(data: Data("invalid archive".utf8))
            XCTFail("Invalid replacement opened")
        } catch {}
        do {
            _ = try await session.setPartXMirrored(true, target: target)
            XCTFail("Mirror edit reached the retained document")
        } catch {
            XCTAssertEqual(error as? PartMirrorError, .staleTarget)
        }
        let retained = try await session.selectComponent("a")
        XCTAssertEqual(retained.documentIdentity, before.documentIdentity)
        XCTAssertEqual(retained.document.encoded(), before.document.encoded())
        XCTAssertFalse(retained.canUndo)
    }

    func testCancellationDoesNotPublish() async throws {
        let doc = try source()
        let session = EditorSession()
        _ = try await session.open(data: doc.encoded())
        let initial = try await session.selectComponent("a")
        let task = Task { try await session.setPartXMirrored(true, target: .init(snapshot: initial, partID: "p")) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled edit published")
        } catch { XCTAssertTrue(error is CancellationError) }
        let unchanged = try await session.selectComponent(nil)
        XCTAssertEqual(unchanged.document.encoded(), doc.encoded())
    }
}
