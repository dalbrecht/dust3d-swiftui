import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class WrappingClipboardSessionTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='n' partId='p' x='.3' y='.5' z='.5' radius='.1'/><node id='m' partId='q' x='.7' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='p'/><part id='q'/></parts><components><component id='garment' name='Garment' wrap='Cloth' wrapBindTo='body' wrapPattern='Future'><component id='gc' linkDataType='partId' linkData='p'/></component><component id='body' name='Body'><component id='bc' linkDataType='partId' linkData='q'/></component></components></canvas>
                """.utf8))
    }
    private func bindings(_ document: Dust3DDocument) throws -> [String: String] {
        let xml = try XMLDocument(data: document.modelXML)
        var pending = xml.rootElement()?.elements(forName: "components").first?.elements(forName: "component") ?? []
        var result: [String: String] = [:]
        while let element = pending.popLast() {
            pending.append(contentsOf: element.elements(forName: "component"))
            if let id = element.attribute(forName: "id")?.stringValue,
                let binding = element.attribute(forName: "wrapBindTo")?.stringValue
            {
                result[id] = binding
            }
        }
        return result
    }
    @MainActor func testNativeAndQtPasteShareCapturedWorkingGroupAndRejectWrongSource() async throws {
        let original = try source()
        let sourceSession = EditorSession()
        _ = try await sourceSession.open(data: original.encoded())
        _ = try await sourceSession.select(["n", "m"])
        let payload = try await sourceSession.copyPayload(identifier: "working")
        let xml = try await sourceSession.copySelection().document.modelXML
        let destinationDocument = try Dust3DDocument(
            snapshotXML: Data("<canvas><components><component id='working'/></components></canvas>".utf8))
        for qt in [false, true] {
            let destination = EditorSession()
            let before = try await destination.open(data: destinationDocument.encoded())
            let target = CanvasAdjustmentTarget(snapshot: before)
            do {
                if qt {
                    _ = try await sourceSession.paste(snapshotXML: xml, parentID: "working", target: target)
                } else {
                    _ = try await sourceSession.paste(data: payload, parentID: "working", target: target)
                }
                XCTFail("A clipboard request acquired another document")
            } catch {
                XCTAssertEqual(error as? WorkingGroupPasteError, .staleTarget)
            }
            let pasted =
                qt
                ? try await destination.paste(snapshotXML: xml, parentID: "working", target: target)
                : try await destination.paste(data: payload, parentID: "working", target: target)
            let garment = try XCTUnwrap(pasted.componentTree.rows.first { $0.component.name == "Garment" }).component
            let body = try XCTUnwrap(pasted.componentTree.rows.first { $0.component.name == "Body" }).component
            XCTAssertEqual(garment.parentID, "working")
            XCTAssertEqual(body.parentID, "working")
            XCTAssertEqual(try bindings(pasted.document)[garment.id], body.id)
            XCTAssertEqual(pasted.selectedIDs.count, 2)
            let undone = try await destination.undo()
            XCTAssertEqual(undone.document.encoded(), destinationDocument.encoded())
            XCTAssertFalse(undone.canUndo)
        }
    }

    @MainActor func testCapturedPasteRejectsRetainedSourceAfterFailedActorOpen() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.select(["n", "m"])
        let payload = try await session.copyPayload(identifier: "retained")
        let target = CanvasAdjustmentTarget(snapshot: selected)
        do {
            _ = try await session.open(data: Data("bad archive".utf8))
            XCTFail("Malformed replacement opened")
        } catch {
            XCTAssertEqual(error as? DocumentError, .invalidArchive)
        }
        do {
            _ = try await session.paste(data: payload, parentID: "garment", target: target)
            XCTFail("A failed replacement kept its prior paste admission")
        } catch {
            XCTAssertEqual(error as? WorkingGroupPasteError, .staleTarget)
        }
        let retained = try await session.select(["n", "m"])
        XCTAssertEqual(retained.document.encoded(), original.encoded())
        XCTAssertFalse(retained.canUndo)
    }

    @MainActor func testNativeAndQtActorPastesRemapCopiedBodyAndPreserveSelectionWithOneUndo() async throws {
        let original = try source()
        for sameDocument in [true, false] {
            for qt in [true, false] {
                let sourceSession = EditorSession()
                _ = try await sourceSession.open(data: original.encoded())
                let selected = try await sourceSession.select(["n", "m"])
                let payload = try await sourceSession.copyPayload(identifier: "bindings")
                let fragment = try await sourceSession.copySelection()
                let destination = sameDocument ? sourceSession : EditorSession()
                let before = sameDocument ? selected : try await destination.open(data: original.encoded())
                let pasted =
                    qt
                    ? try await destination.paste(snapshotXML: fragment.document.modelXML)
                    : try await destination.paste(data: payload)
                let garment = try XCTUnwrap(
                    pasted.componentTree.rows.first { $0.component.name == "Garment" && $0.id != "garment" }
                ).component
                let body = try XCTUnwrap(
                    pasted.componentTree.rows.first { $0.component.name == "Body" && $0.id != "body" }
                ).component
                XCTAssertEqual(try bindings(pasted.document)[garment.id], body.id)
                XCTAssertNotEqual(body.id, "body")
                XCTAssertEqual(pasted.selectedIDs.count, 2)
                XCTAssertTrue(pasted.selectedIDs.isDisjoint(with: ["n", "m"]))
                XCTAssertTrue(pasted.selectedEdgeIDs.isEmpty)
                let sourceUnchanged = try await sourceSession.select(["n", "m"])
                if !sameDocument { XCTAssertEqual(sourceUnchanged.document.encoded(), original.encoded()) }
                let undone = try await destination.undo()
                XCTAssertEqual(undone.document.encoded(), before.document.encoded())
                XCTAssertFalse(undone.canUndo)
                let redone = try await destination.redo()
                XCTAssertEqual(redone.document.encoded(), pasted.document.encoded())
                XCTAssertEqual(try Dust3DDocument(data: redone.document.encoded()).encoded(), redone.document.encoded())
            }
        }
    }
}
