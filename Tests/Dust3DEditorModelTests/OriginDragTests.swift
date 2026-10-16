import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class OriginDragTests: XCTestCase {
    func testProjectionLocksPreviewAndSingleExactUndo() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for plane in EditingPlane.allCases {
            for locks: Set<EditingConstraint> in [[], [.x], [.y], [.z], [.radius], [.x, .y, .z]] {
                let session = EditorSession()
                var snapshot = try await session.open(data: original.encoded())
                for lock in locks { snapshot = try await session.setLock(lock, isLocked: true) }
                let projection = CanvasProjection(
                    bounds: CanvasBounds(nodes: []), plane: plane, width: 472, height: 472)
                let drag = try OriginDrag(snapshot: snapshot, projection: projection)
                let position = drag.position(by: .init(x: 40, y: -80))
                let origin = try XCTUnwrap(snapshot.origin)
                XCTAssertEqual(
                    position.x, origin.x + (plane == .front && !locks.contains(.x) ? 0.1 : 0), accuracy: 0.000001)
                XCTAssertEqual(position.y, origin.y - (locks.contains(.y) ? 0 : 0.2), accuracy: 0.000001)
                XCTAssertEqual(
                    position.z, origin.z + (plane == .side && !locks.contains(.z) ? 0.1 : 0), accuracy: 0.000001)
                let committed = try await session.commitOriginDrag(drag, translation: .init(x: 40, y: -80))
                XCTAssertEqual(committed.origin, position)
                let saved = committed.document.encoded()
                let undone = try await session.undo()
                XCTAssertEqual(undone.document.encoded(), original.encoded())
                XCTAssertFalse(undone.canUndo)
                let redone = try await session.redo()
                XCTAssertEqual(redone.document.encoded(), saved)
            }
        }
    }

    func testOriginDragIgnoresReadonlyPartsAndPreservesOpaqueAssets() async throws {
        let model = Data(
            "<canvas originX='0' originY='0' originZ='0' future='keep'><nodes><node id='a' partId='p' x='1' y='2' z='3' radius='.1'/></nodes><parts><part id='p' locked='true' visible='false' disabled='true'/></parts><future/></canvas>"
                .utf8)
        let asset = Data([0, 255, 17, 42])
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='future.bin' offset='\(model.count)' size='\(asset.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let data =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model + asset
        let session = EditorSession()
        var snapshot = try await session.open(data: data)
        snapshot = try await session.select("a")
        snapshot = try await session.setLock(.radius, isLocked: true)
        XCTAssertFalse(try XCTUnwrap(snapshot.selectedNode).isEditable)
        let drag = try OriginDrag(
            snapshot: snapshot,
            projection: CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .side, width: 472, height: 472))
        let committed = try await session.commitOriginDrag(drag, translation: .init(x: 40, y: 80))
        XCTAssertEqual(committed.nodes, snapshot.nodes)
        XCTAssertEqual(committed.parts, snapshot.parts)
        XCTAssertEqual(committed.selectedID, "a")
        XCTAssertTrue(committed.document.encoded().suffix(asset.count).elementsEqual(asset))
        XCTAssertTrue(String(decoding: committed.document.modelXML, as: UTF8.self).contains("future='keep'"))
        let reopened = try Dust3DDocument(data: committed.document.encoded())
        XCTAssertEqual(try reopened.origin(), committed.origin)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), data)
    }

    func testStaleDragCannotOverwriteChangesLocksReplacementOrAnotherWindow() async throws {
        let session = EditorSession()
        let data = Dust3DDocument.emptyArchive()
        let baseline = try await session.open(data: data)
        let projection = CanvasProjection(bounds: .init(nodes: []), plane: .front, width: 400, height: 400)
        let drag = try OriginDrag(snapshot: baseline, projection: projection)
        _ = try await session.setLock(.x, isLocked: true)
        do {
            _ = try await session.commitOriginDrag(drag, translation: .init(x: 10, y: 10))
            XCTFail()
        } catch { XCTAssertEqual(error as? EditorError, .staleOriginDrag) }
        _ = try await session.setLock(.x, isLocked: false)
        do {
            _ = try await session.commitOriginDrag(drag, translation: .init(x: 10, y: 10))
            XCTFail()
        } catch { XCTAssertEqual(error as? EditorError, .staleOriginDrag) }
        _ = try await session.open(data: data)
        do {
            _ = try await session.commitOriginDrag(drag, translation: .init(x: 10, y: 10))
            XCTFail()
        } catch { XCTAssertEqual(error as? EditorError, .staleOriginDrag) }
        let fresh = try await session.open(data: data)
        let freshDrag = try OriginDrag(snapshot: fresh, projection: projection)
        let changed = try await session.apply([.setOrigin(.init(x: 1, y: 2, z: 3))])
        do {
            _ = try await session.commitOriginDrag(freshDrag, translation: .init(x: 10, y: 10))
            XCTFail()
        } catch { XCTAssertEqual(error as? EditorError, .staleOriginDrag) }
        let other = EditorSession()
        _ = try await other.open(data: data)
        do {
            _ = try await other.commitOriginDrag(drag, translation: .init(x: 10, y: 10))
            XCTFail()
        } catch { XCTAssertEqual(error as? EditorError, .staleOriginDrag) }
        let noop = try await session.apply([])
        XCTAssertEqual(noop.document.encoded(), changed.document.encoded())
    }

    func testNoopAndInvalidDragsPreserveHistoryAndUnavailableOriginRejects() async throws {
        let session = EditorSession()
        let data = Dust3DDocument.emptyArchive()
        let snapshot = try await session.open(data: data)
        let projection = CanvasProjection(bounds: .init(nodes: []), plane: .side, width: 400, height: 400)
        let drag = try OriginDrag(snapshot: snapshot, projection: projection)
        let noop = try await session.commitOriginDrag(drag, translation: .init(x: 0, y: 0))
        XCTAssertFalse(noop.canUndo)
        XCTAssertEqual(noop.document.encoded(), data)
        for delta in [CanvasPoint(x: .nan, y: 0), .init(x: .infinity, y: 0), .init(x: 1e12, y: 0)] {
            do {
                _ = try await session.commitOriginDrag(drag, translation: delta)
                XCTFail()
            } catch { XCTAssertEqual(error as? DocumentError, .invalidOrigin) }
        }
        let unchanged = try await session.apply([])
        XCTAssertEqual(unchanged.document.encoded(), data)
        let model = Data("<canvas/>".utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let unsupported =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
        let unavailable = try await session.open(data: unsupported)
        XCTAssertThrowsError(try OriginDrag(snapshot: unavailable, projection: projection)) {
            XCTAssertEqual($0 as? EditorError, .unavailableOrigin)
        }
        let missing = EditorSession()
        do {
            _ = try await missing.commitOriginDrag(drag, translation: .init(x: 0, y: 0))
            XCTFail()
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
    }
}
