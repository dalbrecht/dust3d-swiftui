import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class ComponentColorImageSessionTests: XCTestCase {
    private var archive: Data {
        let model = Data(
            "<canvas><nodes/><edges/><parts/><components><component id='c'/><component id='other'/></components></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
    }
    private var png: Data {
        get throws {
            try XCTUnwrap(
                Data(
                    base64Encoded:
                        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAAAP9sof2OAAAAAnRSTlOAAToXZeUAAAAKSURBVHicY3AAAABCAEEpN/TvAAAAAElFTkSuQmCC"
                ))
        }
    }
    func testShouldCommitCapturedImageTargetAsOneHistoryStepAndRejectStaleTargets() async throws {
        let session = EditorSession()
        _ = try await session.open(data: archive)
        let selected = try await session.selectComponent("c")
        let target = try XCTUnwrap(ComponentColorImageTarget(snapshot: selected))
        let changed = try await session.importComponentColorImage(png: png, target: target)
        XCTAssertEqual(changed.colorImageAssets.count, 1)
        XCTAssertEqual(changed.selectedComponentID, "c")
        XCTAssertTrue(changed.canUndo)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), archive)
        XCTAssertFalse(undone.canUndo)
        do {
            _ = try await session.importComponentColorImage(png: png, target: target)
            XCTFail("Undo must invalidate a captured source revision")
        } catch { XCTAssertEqual(error as? EditorError, .staleColorImageTarget) }
        let fresh = try XCTUnwrap(ComponentColorImageTarget(snapshot: undone))
        _ = try await session.selectComponent("other")
        do {
            _ = try await session.importComponentColorImage(png: png, target: fresh)
            XCTFail("Selection changed")
        } catch { XCTAssertEqual(error as? EditorError, .staleColorImageTarget) }
        _ = try await session.open(data: archive)
        _ = try await session.selectComponent("c")
        do {
            _ = try await session.importComponentColorImage(png: png, target: fresh)
            XCTFail("Document replaced")
        } catch { XCTAssertEqual(error as? EditorError, .staleColorImageTarget) }
    }
    func testGraphTextureImportsOneSharedAssetClearsAndUndoesExactly() async throws {
        let source = try graphTextureDocument()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let before = try await session.selectGraph(nodes: ["a", "b"], edges: [])
        let target = ComponentMeshSelectionTarget(graphSelection: before)
        let changed = try await session.importComponentColorImages(png: png, target: target)
        let image = try XCTUnwrap(changed.colorImageAssets.first)
        let imageID = try XCTUnwrap(image.imageID)
        XCTAssertEqual(changed.colorImageAssets.count, 1)
        XCTAssertEqual(changed.document.asset(named: image.assetName), try png)
        XCTAssertEqual(
            changed.componentTree.rows.map { $0.component.colorImage }, [.reference(imageID), .reference(imageID)])
        XCTAssertEqual(changed.selectedIDs, before.selectedIDs)
        XCTAssertEqual(changed.previewIdentity.geometry, before.previewIdentity.geometry)
        XCTAssertNotEqual(changed.previewIdentity.materials, before.previewIdentity.materials)
        let current = ComponentMeshSelectionTarget(graphSelection: changed)
        let unchanged = try await session.setComponentColorImages(imageID: imageID, target: current)
        XCTAssertEqual(unchanged.document.encoded(), changed.document.encoded())
        XCTAssertEqual(unchanged.documentRevision, changed.documentRevision)
        let cleared = try await session.setComponentColorImages(imageID: nil, target: current)
        XCTAssertTrue(cleared.componentTree.rows.allSatisfy { $0.component.colorImage == .unset })
        XCTAssertEqual(cleared.document.asset(named: image.assetName), try png)
        let undoClear = try await session.undo()
        XCTAssertEqual(undoClear.document.encoded(), changed.document.encoded())
        let undoImport = try await session.undo()
        XCTAssertEqual(undoImport.document.encoded(), source.encoded())
        XCTAssertFalse(undoImport.canUndo)
        let redo = try await session.redo()
        XCTAssertEqual(redo.document.encoded(), changed.document.encoded())
    }

    func testGraphTextureRejectsUnsupportedAmbiguousAndStaleOwnersWithoutAssets() async throws {
        let session = EditorSession()
        for source in [
            try graphTextureDocument(extraPartAttributes: " target='CutFace'"),
            try graphTextureDocument(extraComponent: "<component id='alias' linkDataType='partId' linkData='p'/>"),
        ] {
            _ = try await session.open(data: source.encoded())
            let selected = try await session.selectGraph(nodes: ["a", "b"], edges: [])
            let target = ComponentMeshSelectionTarget(graphSelection: selected)
            do {
                _ = try await session.importComponentColorImages(png: png, target: target)
                XCTFail("An unsupported or ambiguous texture target committed")
            } catch { XCTAssertEqual(error as? EditorError, .staleColorImageTarget) }
            let unchanged = try await session.selectGraph(nodes: ["a", "b"], edges: [])
            XCTAssertEqual(unchanged.document.encoded(), source.encoded())
            XCTAssertTrue(unchanged.colorImageAssets.isEmpty)
        }
        let source = try graphTextureDocument()
        _ = try await session.open(data: source.encoded())
        let selected = try await session.selectGraph(nodes: ["a", "b"], edges: [])
        let target = ComponentMeshSelectionTarget(graphSelection: selected)
        _ = try await session.select("a")
        _ = try await session.selectGraph(nodes: ["a", "b"], edges: [])
        do {
            _ = try await session.importComponentColorImages(png: png, target: target)
            XCTFail("Selection ABA acquired the old target")
        } catch { XCTAssertEqual(error as? EditorError, .staleColorImageTarget) }
    }

    func testGraphTextureArchivePreservesExistingAssetOffsetsAndRejectsAnyMissingMember() throws {
        let bytes = try png
        let existingID = "{11111111-1111-4111-8111-111111111111}"
        let sharedID = "{22222222-2222-4222-8222-222222222222}"
        let source = try graphTextureDocument().applying(
            .importComponentColorImage(id: "one", imageID: existingID, png: bytes))
        XCTAssertThrowsError(
            try source.applying(.importComponentColorImages(ids: ["one", "missing"], imageID: sharedID, png: bytes))
        ) { XCTAssertEqual($0 as? DocumentError, .missingComponent("missing")) }
        let changed = try source.applying(
            .importComponentColorImages(ids: ["one", "two"], imageID: sharedID, png: bytes))
        XCTAssertEqual(changed.asset(named: "images/\(existingID).png"), bytes)
        XCTAssertEqual(changed.asset(named: "images/\(sharedID).png"), bytes)
    }

    private func graphTextureDocument(extraPartAttributes: String = "", extraComponent: String = "") throws
        -> Dust3DDocument
    {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='.2' y='.5' z='.5' radius='.1'/>
                <node id='b' partId='q' x='.8' y='.5' z='.5' radius='.1'/></nodes>
                <parts><part id='p'/><part id='q'\(extraPartAttributes)/></parts><components>
                <component id='one' linkDataType='partId' linkData='p'/><component id='two' linkDataType='partId' linkData='q'/>
                \(extraComponent)</components></canvas>
                """.utf8))
    }

}
