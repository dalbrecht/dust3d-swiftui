import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ComponentMeshSelectionTests: XCTestCase {
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
