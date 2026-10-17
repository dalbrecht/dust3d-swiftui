import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DKit

final class MeshUvLoaderTests: XCTestCase {
    func testLoadsCopiedMetadataAlignedWithIndexedGeometry() throws {
        for name in ["Capsule", "Sword", "RoundedCrossing"] {
            let data = try fixture(name)
            let result = try MeshLoader.loadWithUvMetadata(data: data)
            XCTAssertEqual(result.metadata.triangles.count, result.geometry.triangleCount)
            XCTAssertFalse(result.metadata.charts.isEmpty)
            XCTAssertTrue(result.metadata.triangles.contains(where: \.hasMapping))
            if name == "RoundedCrossing" {
                XCTAssertTrue(result.metadata.triangles.contains { !$0.hasMapping })
            }
            if name == "Sword" { XCTAssertFalse(result.metadata.gradients.isEmpty) }
            let copied = result.metadata
            let positions = result.geometry.vertices.map(\.position)
            _ = try MeshLoader.loadWithUvMetadata(data: fixture("Sword"))
            _ = try MeshLoader.loadIndexed(data: fixture("Capsule"))
            XCTAssertEqual(result.metadata, copied)
            XCTAssertEqual(result.geometry.vertices.map(\.position), positions)
        }
    }

    func testPreservesNativeQuotaAndMalformedDocumentDiagnostics() throws {
        let data = try fixture("Capsule")
        for budget in [-1, Int.min, 1, 1024, 268_435_457] {
            XCTAssertThrowsError(try MeshLoader.loadWithUvMetadata(data: data, maximumMetadataPayloadBytes: budget)) {
                XCTAssertEqual(($0 as? MeshLoadingError)?.status, budget < 0 ? 1 : 4)
                XCTAssertFalse(($0 as? MeshLoadingError)?.message.isEmpty ?? true)
            }
        }
        for budget in [-1, 1] {
            XCTAssertThrowsError(try MeshLoader.loadWithUvMetadata(data: data, maximumIndexedPayloadBytes: budget)) {
                XCTAssertEqual(($0 as? MeshLoadingError)?.status, budget < 0 ? 1 : 4)
            }
        }
        for size in [0, -1, 8193] {
            XCTAssertThrowsError(try MeshLoader.loadWithUvMetadata(data: data, textureSize: size)) {
                XCTAssertEqual(($0 as? MeshLoadingError)?.status, 1)
            }
        }
        XCTAssertThrowsError(try MeshLoader.loadWithUvMetadata(data: Data())) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 1)
        }
    }

    func testResolvesImageDimensionsAndAlphaWithoutDecodingPixels() throws {
        let imageID = "{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}"
        let data = try archive(attributes: "color='#8000FF00' colorImageId='\(imageID)'")
        let image = MeshUvImageDescriptor(imageID: imageID, width: 64, height: 128)
        let result = try MeshLoader.loadWithUvMetadata(data: data, images: [image])
        let chart = try XCTUnwrap(result.metadata.charts.first)
        XCTAssertEqual(chart.imageID, imageID)
        XCTAssertEqual(chart.color.y, 1)
        XCTAssertEqual(chart.color.w, 128.0 / 255)
        XCTAssertTrue(result.geometry.warning.contains("Untextured"))
        XCTAssertThrowsError(try MeshLoader.loadWithUvMetadata(data: data)) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 2)
            XCTAssertTrue(($0 as? MeshLoadingError)?.message.contains("image") == true)
        }
        let ordinary = try MeshLoader.loadIndexed(data: data)
        XCTAssertGreaterThan(ordinary.triangleCount, 0)
    }

    func testRejectsMalformedImageDescriptorsAndEngineAliases() throws {
        let data = try fixture("Capsule")
        for descriptor in [
            MeshUvImageDescriptor(imageID: "", width: 64, height: 64),
            MeshUvImageDescriptor(imageID: "bad", width: 64, height: 64),
            MeshUvImageDescriptor(imageID: "{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}", width: 0, height: 64),
            MeshUvImageDescriptor(imageID: "{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}", width: 64, height: 8193),
        ] {
            XCTAssertThrowsError(try MeshLoader.loadWithUvMetadata(data: data, images: [descriptor])) {
                XCTAssertEqual(($0 as? MeshLoadingError)?.status, 1)
            }
        }
        let first = MeshUvImageDescriptor(imageID: "{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}", width: 64, height: 64)
        let alias = MeshUvImageDescriptor(imageID: "iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii", width: 64, height: 64)
        XCTAssertThrowsError(try MeshLoader.loadWithUvMetadata(data: data, images: [first, alias])) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 1)
        }
        XCTAssertThrowsError(
            try MeshLoader.loadWithUvMetadata(data: data, images: Array(repeating: first, count: 10001)))
        let upper = MeshUvImageDescriptor(imageID: "{IIIIIIII-IIII-IIII-IIII-IIIIIIIIIIII}", width: 64, height: 64)
        XCTAssertGreaterThan(
            try MeshLoader.loadWithUvMetadata(data: data, images: [first, upper]).geometry.triangleCount, 0)
    }

    func testReportsUnsupportedSourceColorWithoutReplacingIt() throws {
        for color in ["future-color", "#GG1122"] {
            let data = try archive(attributes: "color='\(color)'")
            XCTAssertThrowsError(try MeshLoader.loadWithUvMetadata(data: data)) {
                XCTAssertEqual(($0 as? MeshLoadingError)?.status, 2)
                XCTAssertFalse(($0 as? MeshLoadingError)?.message.isEmpty ?? true)
            }
        }
    }

    @MainActor
    func testCopiesSendableMetadataAcrossConcurrentLoads() async throws {
        let data = try fixture("Capsule")
        let results = try await withThrowingTaskGroup(of: MeshWithUvMetadata.self) { group in
            for _ in 0..<3 { group.addTask { try MeshLoader.loadWithUvMetadata(data: data) } }
            var values: [MeshWithUvMetadata] = []
            for try await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(results.count, 3)
        for result in results { XCTAssertEqual(result.metadata.triangles.count, result.geometry.triangleCount) }
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(
            contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "ds3", subdirectory: "Fixtures")))
    }
    private func archive(attributes: String) throws -> Data {
        let part = "{00000100-0000-4000-8000-000000000100}"
        let xml =
            "<canvas originX='0' originY='0' originZ='0'><nodes><node id='{00001000-0000-4000-8000-000000001000}' partId='\(part)' x='0' y='0' z='0' radius='.1'/></nodes><edges/><parts><part id='\(part)'/></parts><components><component id='{zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz}' linkDataType='partId' linkData='\(part)' \(attributes)/></components></canvas>"
        return try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
    }
}
