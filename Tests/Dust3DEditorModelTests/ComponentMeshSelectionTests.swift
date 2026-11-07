import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ComponentMeshSelectionTests: XCTestCase {
    private func graphDocument(extraComponents: String = "") throws -> Dust3DDocument {
        let xml = """
            <canvas><nodes>
            <node id='n1' partId='p' x='0' y='0' z='0' radius='.1'/>
            <node id='n2' partId='p' x='1' y='0' z='0' radius='.1'/>
            <node id='orphan' x='2' y='0' z='0' radius='.1'/>
            </nodes><edges><edge id='e' partId='q' from='n1' to='n2'/></edges>
            <parts><part id='p'/><part id='q'/></parts><components>
            <component id='group'><component id='ownerP' linkDataType='partId' linkData='p'/></component>
            <component id='ownerQ' linkDataType='partId' linkData='q' combineMode='Inversion'/>
            \(extraComponents)</components></canvas>
            """
        return try Dust3DDocument(snapshotXML: Data(xml.utf8))
    }

    func testGraphOwnerBatchUsesExplicitEdgeOwnerAndKeepsPicksThroughUndo() async throws {
        let source = try graphDocument()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let before = try await session.selectGraph(nodes: ["n1", "n2"], edges: ["e"])
        let target = ComponentMeshSelectionTarget(graphSelection: before)
        let presentation = ComponentMeshSelectionPresentation(snapshot: before, target: target)
        XCTAssertTrue(presentation.isAvailable)
        XCTAssertEqual(presentation.components.map(\.id), ["ownerP", "ownerQ"])
        XCTAssertEqual(presentation.combineMode, .mixed)
        let combined = try await session.editSelectedComponentMeshSettings(.combineMode(.uncombined), target: target)
        let nextTarget = ComponentMeshSelectionTarget(graphSelection: combined)
        let changed = try await session.editSelectedComponentMeshSettings(.smoothCutoffDegrees(42), target: nextTarget)
        let after = ComponentMeshSelectionPresentation(
            snapshot: changed, target: ComponentMeshSelectionTarget(graphSelection: changed))
        XCTAssertEqual(after.combineMode, .uniform(.uncombined))
        XCTAssertEqual(after.smoothCutoffDegrees, .uniform(42))
        XCTAssertEqual(changed.selectedIDs, before.selectedIDs)
        XCTAssertEqual(changed.selectedEdgeIDs, before.selectedEdgeIDs)
        XCTAssertEqual(changed.selectionRevision, before.selectionRevision)
        XCTAssertTrue(changed.selectedComponentIDs.isEmpty)
        let undoCutoff = try await session.undo()
        let undoCombine = try await session.undo()
        XCTAssertEqual(undoCutoff.document.encoded(), combined.document.encoded())
        XCTAssertEqual(undoCombine.document.encoded(), source.encoded())
        XCTAssertEqual(undoCombine.selectedIDs, before.selectedIDs)
        XCTAssertEqual(undoCombine.selectedEdgeIDs, before.selectedEdgeIDs)
        XCTAssertFalse(undoCombine.canUndo)
    }

    func testGraphOwnerColorBatchAndClearPreservePicksAndRejectAmbiguousTargets() async throws {
        let source = try graphDocument()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let before = try await session.selectGraph(nodes: ["n1"], edges: ["e"])
        let target = ComponentMeshSelectionTarget(graphSelection: before)
        let color = DocumentColor(red: 32, green: 64, blue: 96, alpha: 128)
        let colored = try await session.editSelectedComponentColors(color, target: target)
        let rows = colored.componentTree.rows
        XCTAssertEqual(rows.first { $0.id == "group" }?.component.color, .unset)
        XCTAssertEqual(rows.first { $0.id == "ownerP" }?.component.color, .value(color))
        XCTAssertEqual(rows.first { $0.id == "ownerQ" }?.component.color, .value(color))
        XCTAssertEqual(colored.selectedIDs, before.selectedIDs)
        XCTAssertEqual(colored.selectedEdgeIDs, before.selectedEdgeIDs)
        XCTAssertEqual(colored.selectionRevision, before.selectionRevision)
        XCTAssertTrue(colored.selectedComponentIDs.isEmpty)
        let cleared = try await session.editSelectedComponentColors(
            nil, target: ComponentMeshSelectionTarget(graphSelection: colored))
        XCTAssertTrue(cleared.componentTree.rows.allSatisfy { $0.component.color == .unset })
        let restoredColor = try await session.undo()
        XCTAssertEqual(restoredColor.document.encoded(), colored.document.encoded())
        let restoredSource = try await session.undo()
        XCTAssertEqual(restoredSource.document.encoded(), source.encoded())
        XCTAssertFalse(restoredSource.canUndo)

        let duplicate = "<component id='alias' linkDataType='partId' linkData='p'/>"
        let ambiguous = try graphDocument(extraComponents: duplicate)
        _ = try await session.open(data: ambiguous.encoded())
        let selection = try await session.selectGraph(nodes: ["n1"], edges: ["e"])
        for rejected in [target, ComponentMeshSelectionTarget(graphSelection: selection)] {
            do {
                _ = try await session.editSelectedComponentColors(color, target: rejected)
                XCTFail("A stale or ambiguous owner was accepted")
            } catch { XCTAssertEqual(error as? ComponentMeshSelectionError, .staleTarget) }
        }
        let unchanged = try await session.selectGraph(nodes: ["n1"], edges: ["e"])
        XCTAssertEqual(unchanged.document.encoded(), ambiguous.encoded())
        XCTAssertFalse(unchanged.canUndo)
    }

    func testGraphOwnerSingletonUsesStoredEdgeOwnerAndRejectsSelectionABA() throws {
        var state = try EditorState(document: graphDocument())
        try state.selectGraph(nodes: [], edges: ["e"])
        let before = state.snapshot
        let target = ComponentMeshSelectionTarget(graphSelection: before)
        let presentation = ComponentMeshSelectionPresentation(snapshot: before, target: target)
        XCTAssertTrue(presentation.isAvailable)
        XCTAssertEqual(presentation.components.map(\.id), ["ownerQ"])
        XCTAssertFalse(ComponentMeshSelectionTarget(snapshot: before).isCurrent(in: before))

        try state.select("n1")
        try state.selectGraph(nodes: [], edges: ["e"])
        XCTAssertThrowsError(try state.editSelectedComponentMeshSettings(.combineMode(.normal), target: target)) {
            XCTAssertEqual($0 as? ComponentMeshSelectionError, .staleTarget)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), before.document.encoded())
    }

    func testGraphTargetDoesNotSilentlyEditASubsetWithAmbiguousOrMissingOwners() throws {
        let duplicate = "<component id='alias' linkDataType='partId' linkData='p'/>"
        for (source, nodes) in [
            (try graphDocument(extraComponents: duplicate), Set(["n1"])),
            (try graphDocument(), Set(["orphan"])),
        ] {
            var state = try EditorState(document: source)
            try state.selectGraph(nodes: nodes, edges: ["e"])
            let snapshot = state.snapshot
            let target = ComponentMeshSelectionTarget(graphSelection: snapshot)
            XCTAssertFalse(target.isCurrent(in: snapshot))
            XCTAssertFalse(ComponentMeshSelectionPresentation(snapshot: snapshot, target: target).isAvailable)
        }
    }

    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><components><component id='a' inverse='true' smoothCutoffDegrees='090.00'/><component id='b' combineMode='Future' smoothCutoffDegrees='future' linkDataType='future' linkData='opaque'/></components></canvas>"
                    .utf8))
    }
    func testSmoothingIsHiddenWhenDirectLinksResolveToOneCutFace() throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><parts><part id='profile' target='CutFace'/><part id='model'/></parts>
                <components><component id='a' linkDataType='partId' linkData='profile' smoothCutoffDegrees='42'/>
                <component id='b' linkDataType='partId' linkData='profile'/><component id='group'/>
                <component id='c' linkDataType='partId' linkData='model'/></components></canvas>
                """.utf8))
        var state = try EditorState(document: document)
        let rows = state.snapshot.componentTree.rows
        let cutFace = try XCTUnwrap(rows.first { $0.id == "a" }?.component)
        XCTAssertFalse(state.snapshot.showsComponentSmoothing(for: [cutFace]))
        for (ids, expected): (Set<String>, Bool) in [
            (["a", "b"], false), (["a", "group"], false), (["a", "c"], true), (["group"], true),
        ] {
            try state.selectComponents(ids)
            XCTAssertEqual(ComponentMeshSelectionPresentation(snapshot: state.snapshot).showsSmoothing, expected)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), document.encoded())
        XCTAssertEqual(cutFace.smoothCutoffDegrees, 42)
    }

    func testPresentationAndAtomicEditPreserveSelectionLocksNoopAndExactUndo() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectComponents(["a", "b"])
        let presentation = ComponentMeshSelectionPresentation(snapshot: selected)
        XCTAssertEqual(presentation.combineMode, .mixed)
        XCTAssertEqual(presentation.smoothCutoffDegrees, .mixed)
        let locked = try await session.setLock(.x, isLocked: true)
        let after = try await session.editSelectedComponentMeshSettings(
            .smoothCutoffDegrees(90), target: .init(snapshot: locked))
        XCTAssertEqual(after.selectedComponentIDs, ["a", "b"])
        XCTAssertTrue(after.locks.contains(.x))
        XCTAssertEqual(ComponentMeshSelectionPresentation(snapshot: after).smoothCutoffDegrees, .uniform(90))
        let undo = try await session.undo()
        XCTAssertEqual(undo.document.encoded(), original.encoded())
        XCTAssertFalse(undo.canUndo)
        let noop = try await session.editSelectedComponentMeshSettings(
            .combineMode(.inversion), target: .init(snapshot: try await session.selectComponents(["a"])))
        XCTAssertTrue(noop.canRedo)
        XCTAssertEqual(noop.document.encoded(), original.encoded())
    }
    func testCapturedSelectionDocumentConstraintABAAndOtherWindowNeverRetarget() async throws {
        for change in 0..<4 {
            let original = try source()
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            let selected = try await session.selectComponents(["a", "b"])
            let target = ComponentMeshSelectionTarget(snapshot: selected)
            switch change {
            case 0:
                _ = try await session.selectComponent("a")
                _ = try await session.selectComponents(["a", "b"])
            case 1:
                _ = try await session.setLock(.x, isLocked: true)
                _ = try await session.setLock(.x, isLocked: false)
            case 2: _ = try await session.open(data: original.encoded())
            default:
                let other = EditorSession()
                _ = try await other.open(data: original.encoded())
                do {
                    _ = try await other.editSelectedComponentMeshSettings(.combineMode(.normal), target: target)
                    XCTFail("Cross window")
                } catch { XCTAssertEqual(error as? ComponentMeshSelectionError, .staleTarget) }
                continue
            }
            do {
                _ = try await session.editSelectedComponentMeshSettings(.combineMode(.normal), target: target)
                XCTFail("Stale target")
            } catch { XCTAssertEqual(error as? ComponentMeshSelectionError, .staleTarget) }
        }
    }
    func testUnavailableAndExactAliasTargetsNeverAcquireSelectionAndCancellationDoesNotPublish() async throws {
        let original = try source()
        let session = EditorSession()
        let empty = try await session.open(data: original.encoded())
        let unavailable = ComponentMeshSelectionTarget(snapshot: empty)
        let absent = ComponentMeshSelectionPresentation(snapshot: empty)
        XCTAssertFalse(absent.isAvailable)
        XCTAssertTrue(absent.components.isEmpty)
        XCTAssertEqual(absent.combineMode, .unsupported)
        XCTAssertEqual(absent.smoothCutoffDegrees, .unsupported)
        let selected = try await session.selectComponents(["a", "b"])
        XCTAssertFalse(unavailable.isCurrent(in: selected))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.editSelectedComponentMeshSettings(
                .combineMode(.normal), target: .init(snapshot: selected))
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled edit")
        } catch { XCTAssertTrue(error is CancellationError) }
        let current = try await session.selectComponents(["a", "b"])
        XCTAssertEqual(current.document.encoded(), original.encoded())
        XCTAssertFalse(current.canUndo)
        let doc = try Dust3DDocument(
            snapshotXML: Data("<canvas><components><component id='cafe&#769;'/></components></canvas>".utf8))
        var state = try EditorState(document: doc)
        try state.selectComponents(["caf\u{e9}"])
        XCTAssertFalse(ComponentMeshSelectionTarget(snapshot: state.snapshot).isCurrent(in: state.snapshot))
    }
    func testUniformEffectiveDefaultsLegacyModesAndUnknownSourcesStayInformational() throws {
        for (a, b, mode, cutoff):
            (String, String, ComponentMeshSelectionValue<ComponentCombineMode>, ComponentMeshSelectionValue<Double>)
            in [
                ("", "combineMode='' smoothCutoffDegrees='-0'", .uniform(.normal), .uniform(0)),
                (
                    "inverse='True' smoothCutoffDegrees='090.00'", "combineMode='Inversion' smoothCutoffDegrees='90'",
                    .uniform(.inversion), .uniform(90)
                ),
                (
                    "combineMode='FutureA' smoothCutoffDegrees='future-a'",
                    "combineMode='FutureB' smoothCutoffDegrees='future-b'", .unsupported, .unsupported
                ),
            ]
        {
            let original = try Dust3DDocument(
                snapshotXML: Data(
                    "<canvas><components><component id='a' \(a)/><component id='b' \(b)/></components></canvas>".utf8))
            var state = try EditorState(document: original)
            try state.selectComponents(["a", "b"])
            let presentation = ComponentMeshSelectionPresentation(snapshot: state.snapshot)
            XCTAssertEqual(presentation.combineMode, mode)
            XCTAssertEqual(presentation.smoothCutoffDegrees, cutoff)
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }

}
