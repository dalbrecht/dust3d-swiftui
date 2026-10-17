import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class ComponentReparentTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><components><component id='assembly' name='Assembly'><component id='source' name='Source'><component id='child'/></component><component id='sibling' name='Sibling'/></component><component id='other' name='Destination'/><component id='opaque' linkDataType='future'/></components></canvas>
                """.utf8))
    }

    func testParentOptionsExcludeSelfDescendantsCurrentParentAndUnsupportedLinks() throws {
        let tree = ComponentTree(document: try document())
        XCTAssertEqual(
            tree.parentOptions(for: "source").map(\.id), [.root, .component("sibling"), .component("other")])
        XCTAssertEqual(tree.parentOptions(for: "source", matching: "  OTHER  ").map(\.id), [.component("other")])
        XCTAssertEqual(tree.parentOptions(for: "source", matching: "sibling").first?.title, "Sibling")
        XCTAssertEqual(tree.parentOptions(for: "source", matching: "document root").first?.id, .root)
        XCTAssertTrue(tree.parentOptions(for: "source", matching: "missing").isEmpty)
        XCTAssertEqual(tree.parentOptions(for: "assembly").map(\.id), [.component("other")])
        XCTAssertTrue(tree.parentOptions(for: "missing").isEmpty)
        XCTAssertNil(ComponentParent.root.componentID)
        XCTAssertEqual(ComponentParent.component("other").componentID, "other")
    }

    func testReparentTargetRejectsChangedDocumentRevisionWindowAndSelectionAtomically() throws {
        let original = try document()
        var state = try EditorState(document: original)
        XCTAssertNil(ComponentReparentTarget(snapshot: state.snapshot))
        try state.selectComponent("source")
        let target = try XCTUnwrap(ComponentReparentTarget(snapshot: state.snapshot))
        XCTAssertTrue(target.isCurrent(in: state.snapshot))
        var other = try EditorState(document: original)
        try other.selectComponent("source")
        XCTAssertFalse(target.isCurrent(in: other.snapshot))
        try state.selectComponents(["source", "sibling"])
        XCTAssertThrowsError(try state.reparentComponent(to: .component("other"), target: target)) {
            XCTAssertEqual($0 as? EditorError, .staleComponentMove)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        try state.selectComponent("source")
        try state.apply([.setComponentName(id: "source", name: "Changed")])
        XCTAssertFalse(target.isCurrent(in: state.snapshot))
        XCTAssertThrowsError(try state.reparentComponent(to: .root, target: target))
        try state.undo()
        XCTAssertFalse(target.isCurrent(in: state.snapshot))
        let fresh = try XCTUnwrap(ComponentReparentTarget(snapshot: state.snapshot))
        XCTAssertThrowsError(try state.reparentComponent(to: .component("child"), target: fresh)) {
            XCTAssertEqual($0 as? DocumentError, .invalidComponentStructure)
        }
        XCTAssertThrowsError(try state.reparentComponent(to: .component("missing"), target: fresh))
        try state.reparentComponent(to: .component("other"), target: fresh)
        XCTAssertEqual(state.snapshot.selectedComponent?.parentID, "other")
        XCTAssertEqual(state.snapshot.selectedComponentID, "source")
        let changed = state.snapshot.document.encoded()
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        try state.redo()
        XCTAssertEqual(state.snapshot.document.encoded(), changed)
    }

    func testActorReparentsSelectedComponentToRootInOneHistoryStep() async throws {
        let session = EditorSession()
        let original = try document()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectComponent("source")
        let target = try XCTUnwrap(ComponentReparentTarget(snapshot: selected))
        let moved = try await session.reparentComponent(to: .root, target: target)
        XCTAssertNil(moved.selectedComponent?.parentID)
        XCTAssertEqual(moved.selectedComponent?.childIDs, ["child"])
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
    }
}
