import Dust3DDocument
import Dust3DKit
import Foundation
import XCTest
import simd

final class ComponentWrappingCompatibilityTests: XCTestCase {
    private let groupID = "{00000300-0000-4000-8000-000000000300}"
    // Independently serialized synthetic one-sphere source, without commands under test.
    private func document(_ mode: String = "") throws -> Dust3DDocument {
        let partID = "{00000100-0000-4000-8000-000000000100}"
        let model = Data(
            "<canvas originX='.5' originY='.5' originZ='.5'><nodes><node id='{00001000-0000-4000-8000-000000001000}' partId='\(partID)' x='.5' y='.5' z='.5' radius='.2'/></nodes><edges/><parts><part id='\(partID)'/></parts><components><component id='\(groupID)' wrap='\(mode)' wrapFaces='64'><component id='{00000200-0000-4000-8000-000000000200}' linkDataType='partId' linkData='\(partID)'/></component></components></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model)
    }
    private func mesh(_ document: Dust3DDocument) throws -> Mesh {
        let mesh = try MeshLoader.load(data: document.encoded())
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        XCTAssertEqual(mesh.nodeCount, 1)
        XCTAssertEqual(mesh.partCount, 1)
        for vertex in mesh.vertices {
            for axis in 0..<3 { XCTAssertTrue(vertex.position[axis].isFinite) }
            XCTAssertEqual(simd_length(vertex.normal), 1, accuracy: 0.0001)
        }
        return mesh
    }
    func testModesFacesKeepChildrenAndHistoryChangeRealFiniteGeometry() throws {
        let source = try document()
        let baseline = try mesh(source)
        for mode in [ComponentWrapMode.skin, .cloth] {
            var history = DocumentHistory(document: source)
            try history.apply(.setComponentWrapMode(id: groupID, mode: mode))
            let changed = history.document
            let wrapped = try mesh(changed)
            XCTAssertNotEqual(wrapped.triangleCount, baseline.triangleCount)
            let denser = try mesh(changed.applying(.setComponentWrapFaces(id: groupID, faces: 256)))
            XCTAssertGreaterThan(denser.triangleCount, wrapped.triangleCount)
            let keep = try mesh(changed.applying(.setComponentWrapKeepChildren(id: groupID, value: true)))
            let replace = try mesh(changed.applying(.setComponentWrapKeepChildren(id: groupID, value: false)))
            XCTAssertGreaterThan(keep.triangleCount, replace.triangleCount)
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertEqual(try mesh(history.document).triangleCount, baseline.triangleCount)
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
            XCTAssertEqual(try mesh(history.document).triangleCount, wrapped.triangleCount)
        }
    }
    func testConfiguredClothScalarsRemainFiniteAndOffsetChangesSurfaceBounds() throws {
        let source = try document("Cloth")
        let baseline = try mesh(source)
        for property in ComponentWrappingScalarProperty.allCases {
            let value = [.openTop, .openBottom].contains(property) ? 0.1 : property.bounds.upperBound / 2
            let changed = try source.applying(.setComponentWrapScalar(id: groupID, property: property, value: value))
            let configured: Mesh
            do { configured = try mesh(changed) } catch {
                XCTFail("Wrapping scalar \(property.rawValue) failed: \(error)")
                continue
            }
            XCTAssertEqual(try changed.editorContents().nodes, try source.editorContents().nodes)
            if property == .offset {
                let oldMaximum = try XCTUnwrap(baseline.vertices.map { $0.position.x }.max())
                let newMaximum = try XCTUnwrap(configured.vertices.map { $0.position.x }.max())
                XCTAssertGreaterThan(newMaximum, oldMaximum + 0.01)
            }
        }
    }
    func testLowDensityMidpointOpeningsGenerateFiniteGeometryAfterAngleRepair() throws {
        // Reviewed core #15 repairs the numerical failure; topology quality remains core #14.
        let source = try document("Cloth")
        for property in [ComponentWrappingScalarProperty.openTop, .openBottom] {
            let changed = try source.applying(.setComponentWrapScalar(id: groupID, property: property, value: 0.225))
            _ = try mesh(changed)
            let denser = try changed.applying(.setComponentWrapFaces(id: groupID, faces: 256))
            _ = try mesh(denser)
        }
    }
    func testNewCorePinRejectsPreviouslyUncheckedWrappingNumbers() throws {
        let source = try document("Skin")
        let xml = String(decoding: source.modelXML, as: UTF8.self).replacingOccurrences(
            of: "wrapFaces=", with: "wrapSmoothness='nan' wrapFaces=")
        let model = Data(xml.utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let bytes =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
        XCTAssertThrowsError(try MeshLoader.load(data: bytes)) { XCTAssertEqual(($0 as? MeshLoadingError)?.status, 1) }
    }
}
