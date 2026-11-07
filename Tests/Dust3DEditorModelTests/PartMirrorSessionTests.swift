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
    private func graphSource(flag: String = "0", duplicateOwner: Bool = false) throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.125'/>
                <node id='b' partId='p' x='2' y='0' z='0' radius='.125'/>
                <node id='c' partId='q' x='4' y='0' z='0' radius='.125'/>
                </nodes><edges><edge id='ab' partId='p' from='a' to='b'/></edges>
                <parts><part id='p' xMirrored='\(flag)' locked='true' unknown='keep'/><part id='q' target='CutFace'/></parts>
                <components><component id='cp' linkDataType='partId' linkData='p'/>
                <component id='cq' linkDataType='partId' linkData='q'/>
                \(duplicateOwner ? "<component id='second' linkDataType='partId' linkData='p'/>" : "")
                </components></canvas>
                """.utf8))
    }

    func testGraphMirrorRequiresOneUniqueModelOwner() throws {
        var state = try EditorState(document: graphSource())
        try state.selectGraph(nodes: ["a"], edges: ["ab"])
        let target = PartMirrorTarget(graphTarget: GraphModelPartTarget(snapshot: state.snapshot))
        XCTAssertEqual(target.partID, "p")
        XCTAssertTrue(target.isCurrent(in: state.snapshot))
        XCTAssertNil(state.snapshot.mirrorInspectorPart)

        try state.selectGraph(nodes: ["c"], edges: ["ab"])
        XCTAssertNil(PartMirrorTarget(graphTarget: GraphModelPartTarget(snapshot: state.snapshot)).partID)
        try state.select("c")
        XCTAssertNil(PartMirrorTarget(graphTarget: GraphModelPartTarget(snapshot: state.snapshot)).partID)
        var duplicate = try EditorState(document: graphSource(duplicateOwner: true))
        try duplicate.selectEdges(["ab"])
        XCTAssertNil(PartMirrorTarget(graphTarget: GraphModelPartTarget(snapshot: duplicate.snapshot)).partID)
    }

    func testGraphMirrorPreservesPicksAndSettlesOriginInOneUndo() async throws {
        let original = try graphSource()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selection = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        let target = PartMirrorTarget(graphTarget: GraphModelPartTarget(snapshot: selection))
        let unchanged = try await session.setPartXMirrored(false, target: target)
        XCTAssertEqual(unchanged.document.encoded(), original.encoded())
        XCTAssertNil(unchanged.origin)
        XCTAssertFalse(unchanged.canUndo)

        let mirrored = try await session.setPartXMirrored(true, target: target)
        XCTAssertEqual(mirrored.parts.first?.xMirrored, true)
        XCTAssertEqual(mirrored.origin, .init(x: 2, y: 0, z: 0))
        XCTAssertEqual(mirrored.selectedIDs, ["a"])
        XCTAssertEqual(mirrored.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(mirrored.nodes, selection.nodes)
        let model = try XMLDocument(data: mirrored.document.modelXML)
        let part = try XCTUnwrap(try model.nodes(forXPath: "//part[@id='p']").first as? XMLElement)
        XCTAssertEqual(part.attribute(forName: "unknown")?.stringValue, "keep")
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
    }

    func testGraphMirrorPreservesUnsupportedLexemeUntilAcceptedExplicitEdit() async throws {
        let original = try graphSource(flag: "future")
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let first = try await session.selectEdges(["ab"])
        let stale = PartMirrorTarget(graphTarget: GraphModelPartTarget(snapshot: first))
        XCTAssertNil(first.parts.first?.xMirrored)
        _ = try await session.select("c")
        let current = try await session.selectEdges(["ab"])
        do {
            _ = try await session.setPartXMirrored(false, target: stale)
            XCTFail("A retired selection acquired a mirror edit")
        } catch { XCTAssertEqual(error as? PartMirrorError, .staleTarget) }
        let target = PartMirrorTarget(graphTarget: GraphModelPartTarget(snapshot: current))
        do {
            _ = try await session.open(data: Data("bad archive".utf8))
            XCTFail("Invalid replacement opened")
        } catch {}
        do {
            _ = try await session.setPartXMirrored(false, target: target)
            XCTFail("A retired document acquired a mirror edit")
        } catch { XCTAssertEqual(error as? PartMirrorError, .staleTarget) }
        let retained = try await session.selectEdges(["ab"])
        XCTAssertEqual(retained.document.encoded(), original.encoded())
        XCTAssertNil(retained.parts.first?.xMirrored)
        XCTAssertFalse(retained.canUndo)
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
