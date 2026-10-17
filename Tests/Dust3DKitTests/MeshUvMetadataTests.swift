import XCTest

@testable import Dust3DKit

final class MeshUvMetadataTests: XCTestCase {
    private let componentID = "{zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz}"
    private var corners: MeshUvCorners {
        MeshUvCorners(first: SIMD2(0, 0), second: SIMD2(1, 0), third: SIMD2(0, 1))
    }
    private func triangle(known: UInt8 = 1, kind: UInt32 = 1, index: Int = 0) -> RawMeshUvTriangle {
        RawMeshUvTriangle(corners: corners, known: known, componentKind: kind, componentIndex: index)
    }
    private func chart(
        flipped: UInt8 = 0, imageID: String? = nil, origin: SIMD2<Double> = .zero,
        size: SIMD2<Double> = SIMD2(1, 1), color: SIMD4<Double> = SIMD4(1, 0.5, 0, 0.25),
        kind: UInt32 = 1, index: Int = 0
    ) -> RawMeshUvChart {
        RawMeshUvChart(
            origin: origin, size: size, color: color,
            flipped: flipped, componentKind: kind, componentIndex: index, imageID: imageID)
    }
    private func metadata(
        identifiers: [String]? = nil, triangles: [RawMeshUvTriangle]? = nil,
        charts: [RawMeshUvChart]? = nil, gradients: [MeshUvGradient] = [],
        vertices: Int = 3, textureSize: Double = 4096
    ) throws -> MeshUvMetadata {
        try MeshUvMetadata(
            componentIDs: identifiers ?? [componentID], triangles: triangles ?? [triangle()],
            charts: charts ?? [chart()], gradients: gradients,
            expandedVertexCount: vertices, packedTextureSize: textureSize)
    }
    private func assertError(_ error: MeshUvDataError, operation: () throws -> Void) {
        XCTAssertThrowsError(try operation()) { XCTAssertEqual($0 as? MeshUvDataError, error) }
    }

    func testCopiesValidatedCornersSourceColorAndIdentity() throws {
        let value = try metadata()
        XCTAssertEqual(value.components[0].componentID, componentID)
        XCTAssertEqual(value.triangles[0].corners, corners)
        XCTAssertTrue(value.triangles[0].hasMapping)
        XCTAssertEqual(value.triangles[0].component.kind, .component)
        XCTAssertEqual(value.triangles[0].component.identityIndex, 0)
        XCTAssertEqual(value.charts[0].color.w, 0.25)
        XCTAssertEqual(value.packedTextureSize, 4096)
    }

    func testPreservesUnmappedAndAmbiguousStatesWithoutInventingIndices() throws {
        let zero = MeshUvCorners(first: .zero, second: .zero, third: .zero)
        let missing = RawMeshUvTriangle(corners: zero, known: 0, componentKind: 2, componentIndex: -1)
        let value = try metadata(triangles: [missing], charts: [], textureSize: 0)
        XCTAssertFalse(value.triangles[0].hasMapping)
        XCTAssertEqual(value.triangles[0].component.kind, .ambiguous)
        XCTAssertNil(value.triangles[0].component.identityIndex)
        let unknown = try metadata(triangles: [triangle(kind: 0, index: -1)])
        XCTAssertEqual(unknown.triangles[0].component.kind, .unknown)
    }

    func testPreservesFutureComponentKindsAndBoundedReferences() throws {
        let value = try metadata(triangles: [triangle(kind: 99)])
        XCTAssertEqual(value.triangles[0].component.kind, .unrecognized(99))
        XCTAssertEqual(value.triangles[0].component.identityIndex, 0)
        let missing = try metadata(triangles: [triangle(kind: 99, index: -1)])
        XCTAssertNil(missing.triangles[0].component.identityIndex)
        assertError(.invalidComponentIdentity) { _ = try self.metadata(triangles: [self.triangle(kind: 99, index: 1)]) }
    }

    func testRejectsInvalidGeometryAndTriangleCounts() {
        for count in [0, -1, 1, 4] {
            assertError(.invalidGeometryCount) { _ = try self.metadata(vertices: count) }
        }
        assertError(.invalidTriangleCount) { _ = try self.metadata(triangles: []) }
        assertError(.invalidTriangleCount) { _ = try self.metadata(vertices: 6) }
    }

    func testRejectsInvalidMappingMarkersAndAssociations() {
        assertError(.invalidMappingMarker) { _ = try self.metadata(triangles: [self.triangle(known: 2)]) }
        for (kind, index): (UInt32, Int) in [(1, -1), (1, 1), (0, 0), (2, 0), (99, -2)] {
            assertError(.invalidComponentIdentity) {
                _ = try self.metadata(triangles: [self.triangle(kind: kind, index: index)])
            }
        }
        assertError(.invalidChart) { _ = try self.metadata(charts: [], textureSize: 0) }
    }

    func testRejectsNonfiniteOrOutOfRangeCorners() {
        for value in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
            let invalid = RawMeshUvTriangle(
                corners: MeshUvCorners(first: SIMD2(value, 0), second: corners.second, third: corners.third),
                known: 1, componentKind: 1, componentIndex: 0)
            assertError(.invalidCoordinate) { _ = try self.metadata(triangles: [invalid]) }
        }
        let missing = RawMeshUvTriangle(corners: corners, known: 0, componentKind: 0, componentIndex: -1)
        assertError(.invalidCoordinate) { _ = try self.metadata(triangles: [missing]) }
    }

    func testRejectsEmptyDuplicateAndOversizedIdentifiers() {
        for identifiers in [[""], [componentID, componentID], [String(repeating: "a", count: 39)]] {
            assertError(.invalidIdentity) { _ = try self.metadata(identifiers: identifiers) }
        }
    }

    func testOpaqueImageIdentityEqualityPreservesExactBytes() throws {
        let first = "e\u{301}\u{327}aaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let second = "e\u{327}\u{301}aaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.utf8.count, 36)
        let value = try metadata(identifiers: [first, second])
        XCTAssertNotEqual(value.components[0], value.components[1])
        let firstImage = try metadata(charts: [chart(imageID: first)])
        let secondImage = try metadata(charts: [chart(imageID: second)])
        XCTAssertNotEqual(firstImage.charts[0], secondImage.charts[0])
        XCTAssertNotEqual(firstImage, secondImage)
    }

    func testRejectsInvalidTextureScaleAndChartFlags() {
        for value in [Double.nan, .infinity, 0, -1] {
            assertError(.invalidTextureSize) { _ = try self.metadata(textureSize: value) }
        }
        assertError(.invalidChart) { _ = try self.metadata(charts: [self.chart(flipped: 2)]) }
        assertError(.invalidIdentity) { _ = try self.metadata(charts: [self.chart(imageID: "")]) }
    }

    func testValidatesEveryChartAxisColorAndAssociation() throws {
        for value in [Double.nan, .infinity, -0.01, 1.01] {
            for axis in 0..<2 {
                var position = SIMD2<Double>.zero
                position[axis] = value
                assertError(.invalidChart) { _ = try self.metadata(charts: [self.chart(origin: position)]) }
                var size = SIMD2<Double>(1, 1)
                size[axis] = value
                assertError(.invalidChart) { _ = try self.metadata(charts: [self.chart(size: size)]) }
            }
            for channel in 0..<4 {
                var color = SIMD4<Double>(1, 1, 1, 1)
                color[channel] = value
                assertError(.invalidChart) { _ = try self.metadata(charts: [self.chart(color: color)]) }
            }
        }
        for size in [SIMD2<Double>(0, 1), SIMD2<Double>(1, 0)] {
            assertError(.invalidChart) { _ = try self.metadata(charts: [self.chart(size: size)]) }
        }
        for position in [SIMD2<Double>(0.1, 0), SIMD2<Double>(0, 0.1)] {
            assertError(.invalidChart) { _ = try self.metadata(charts: [self.chart(origin: position)]) }
        }
        let rounded = try metadata(charts: [chart(flipped: 1, origin: SIMD2(0.0000001, 0))])
        XCTAssertTrue(rounded.charts[0].isFlipped)
        let future = try metadata(charts: [chart(kind: 77, index: -1)])
        XCTAssertEqual(future.charts[0].component.kind, .unrecognized(77))
        assertError(.invalidComponentIdentity) { _ = try self.metadata(charts: [self.chart(index: -1)]) }
        assertError(.invalidIdentity) { _ = try self.metadata(identifiers: ["component\0suffix"]) }
        assertError(.invalidIdentity) { _ = try self.metadata(charts: [self.chart(imageID: "image\0suffix")]) }
    }

    func testValidatesAllCornerPositionsAndGradientChannels() throws {
        for corner in 0..<3 {
            for axis in 0..<2 {
                var positions = [corners.first, corners.second, corners.third]
                positions[corner][axis] = .nan
                let invalid = RawMeshUvTriangle(
                    corners: MeshUvCorners(first: positions[0], second: positions[1], third: positions[2]),
                    known: 1, componentKind: 1, componentIndex: 0)
                assertError(.invalidCoordinate) { _ = try self.metadata(triangles: [invalid]) }
            }
        }
        for channel in 0..<4 {
            for value in [Double.nan, .infinity, -0.1, 1.1] {
                var color = SIMD4<Double>(0, 0, 0, 1)
                color[channel] = value
                for isLarge in [false, true] {
                    let gradient = MeshUvGradient(
                        chartIndex: 0, largeColor: isLarge ? color : .zero,
                        smallColor: isLarge ? .zero : color, resolution: 512)
                    assertError(.invalidGradient) { _ = try self.metadata(gradients: [gradient]) }
                }
            }
        }
        let gradient = MeshUvGradient(chartIndex: 0, largeColor: .zero, smallColor: .zero, resolution: 512)
        assertError(.invalidGradient) {
            _ = try self.metadata(charts: [self.chart(imageID: self.componentID)], gradients: [gradient])
        }
    }

    func testChartEqualityIncludesNumericSourceAndOptionalImageFields() throws {
        let base = try metadata().charts[0]
        XCTAssertEqual(base, base)
        for changed in [
            chart(origin: SIMD2(0.1, 0), size: SIMD2(0.9, 1)), chart(size: SIMD2(0.5, 1)),
            chart(color: .zero), chart(flipped: 1), chart(kind: 0, index: -1), chart(imageID: componentID),
        ] {
            let value = try metadata(charts: [changed]).charts[0]
            XCTAssertNotEqual(base, value)
            XCTAssertNotEqual(value, base)
        }
    }

    func testKeepsIndependentGradientOrdinalsAndAlpha() throws {
        let gradient = MeshUvGradient(
            chartIndex: 0, largeColor: SIMD4(1, 0, 0, 0.5), smallColor: SIMD4(0, 0, 1, 1), resolution: 512)
        let value = try metadata(gradients: [gradient])
        XCTAssertEqual(value.gradients, [gradient])
        XCTAssertEqual(value.gradients[0].largeColor.w, 0.5)
        for index in [-1, 1] {
            let invalid = MeshUvGradient(
                chartIndex: index, largeColor: .zero, smallColor: .zero, resolution: 512)
            assertError(.invalidGradient) { _ = try self.metadata(gradients: [invalid]) }
        }
        assertError(.invalidGradient) { _ = try self.metadata(gradients: [gradient, gradient]) }
        for resolution in [0, 8193] {
            let invalid = MeshUvGradient(
                chartIndex: 0, largeColor: .zero, smallColor: .zero, resolution: resolution)
            assertError(.invalidGradient) { _ = try self.metadata(gradients: [invalid]) }
        }
    }
}
