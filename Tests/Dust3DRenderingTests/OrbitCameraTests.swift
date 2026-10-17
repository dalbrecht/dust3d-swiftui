import Dust3DDocument
import Dust3DKit
import XCTest
import simd

@testable import Dust3DRendering

final class OrbitCameraTests: XCTestCase {
    private func isInside(_ point: SIMD3<Float>, transform: simd_float4x4) -> Bool {
        let clip = transform * SIMD4(point, 1)
        return clip.x.isFinite && clip.y.isFinite && clip.z.isFinite && clip.w.isFinite
            && clip.w > 0 && abs(clip.x) <= clip.w + 0.0001 && abs(clip.y) <= clip.w + 0.0001
            && clip.z >= 0 && clip.z <= clip.w + 0.0001
    }

    func testDefaultCameraFitsTheUnitSphereAcrossNarrowAndWideViewports() {
        let camera = OrbitCamera()
        let surface = (0..<512).map { index -> SIMD3<Float> in
            let height = 1 - 2 * (Float(index) + 0.5) / 512
            let radius = sqrt(1 - height * height)
            let angle = Float(index) * .pi * (3 - sqrt(5))
            return SIMD3(radius * cos(angle), height, radius * sin(angle))
        }
        for aspect: Float in [0.01, 0.1, 0.46, 1, 2, 8] {
            let transform = camera.transform(aspect: aspect)
            XCTAssertTrue(
                surface.allSatisfy { isInside($0, transform: transform) }, "Clipped sphere at aspect \(aspect)")
        }
    }

    func testAspectChangesPreserveOrbitAndRelativeZoomWithoutMutatingCameraState() {
        var camera = OrbitCamera()
        camera.orbit(horizontal: 12, vertical: 6)
        camera.zoom(delta: 10)
        let distance = camera.distance
        let center = SIMD4<Float>(0, 0, 0, 1)
        let narrow = camera.transform(aspect: 0.5) * center
        let square = camera.transform(aspect: 1) * center
        let wide = camera.transform(aspect: 4) * center
        XCTAssertGreaterThan(narrow.w, square.w)
        let baseline = OrbitCamera().transform(aspect: 0.5) * center
        XCTAssertEqual(narrow.w / baseline.w, distance / 3, accuracy: 0.0001)
        XCTAssertEqual(wide.w, square.w, accuracy: 0.0001)
        XCTAssertEqual(camera.distance, distance)
        XCTAssertEqual(camera.yaw, -0.23, accuracy: 0.0001)
        XCTAssertEqual(camera.pitch, 0.21, accuracy: 0.0001)
        XCTAssertEqual(distance, 3 * exp(-0.3), accuracy: 0.0001)
    }

    func testNarrowViewportDepthRangeAndBoundedZoomKeepTheModelCenterVisible() {
        var camera = OrbitCamera()
        camera.zoom(delta: -10_000)
        XCTAssertEqual(camera.distance, 20)
        XCTAssertTrue(isInside(.zero, transform: camera.transform(aspect: 0.01)))
        camera.zoom(delta: 10_000)
        XCTAssertEqual(camera.distance, 1.25)
        camera.orbit(horizontal: 0, vertical: 10_000)
        XCTAssertEqual(camera.pitch, 1.5)
        camera.orbit(horizontal: 0, vertical: -10_000)
        XCTAssertEqual(camera.pitch, -1.5)
        XCTAssertTrue(isInside(.zero, transform: camera.transform(aspect: 0.01)))
    }

    func testExtremePortraitZoomRetainsDistinctFrontAndBackDepths() {
        for zoom: Float in [0, -10_000] {
            var camera = OrbitCamera()
            camera.zoom(delta: zoom)
            let transform = camera.transform(aspect: 0.01) * camera.rotation.inverse
            let front = transform * SIMD4<Float>(0, 0, 1, 1)
            let center = transform * SIMD4<Float>(0, 0, 0, 1)
            let back = transform * SIMD4<Float>(0, 0, -1, 1)
            let frontDepth = front.z / front.w
            let centerDepth = center.z / center.w
            let backDepth = back.z / back.w
            XCTAssertGreaterThan(frontDepth, 0)
            XCTAssertLessThan(backDepth, 1)
            XCTAssertGreaterThan(centerDepth - frontDepth, 0.000001)
            XCTAssertGreaterThan(backDepth - centerDepth, 0.000001)
        }
    }

    func testUnavailableOrNonfiniteViewportAspectsProduceFiniteProjection() {
        let camera = OrbitCamera()
        for aspect: Float in [0, -1, .nan, .infinity, -.infinity] {
            let transform = camera.transform(aspect: aspect)
            for column in [transform.columns.0, transform.columns.1, transform.columns.2, transform.columns.3] {
                XCTAssertTrue((0..<4).allSatisfy { column[$0].isFinite })
            }
            XCTAssertTrue(isInside(.zero, transform: transform))
        }
    }

    func testDisjointNativeSpheresFitThePortraitEditorPreview() throws {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (node, part, component, x) in [
            (
                "{11111111-1111-4111-8111-111111111111}", "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", 0.5
            ),
            (
                "{22222222-2222-4222-8222-222222222222}", "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}",
                "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}", 3.0
            ),
        ] {
            document = try document.applying(
                .addNode(
                    id: node, partID: part, componentID: component, position: .init(x: x, y: 0.5, z: 0.5), radius: 0.1))
        }
        let mesh = try MeshLoader.load(data: document.encoded())
        XCTAssertEqual(mesh.triangleCount, 32)
        let positions = mesh.vertices.map(\.position)
        let minimum = positions.reduce(SIMD3<Float>(repeating: .infinity), simd_min)
        let maximum = positions.reduce(SIMD3<Float>(repeating: -.infinity), simd_max)
        let center = (minimum + maximum) * 0.5
        let radius = simd_length(maximum - minimum) * 0.5
        XCTAssertGreaterThan(radius, 0)
        let transform = OrbitCamera().transform(aspect: 0.46)
        XCTAssertTrue(positions.allSatisfy { isInside(($0 - center) / radius, transform: transform) })
    }
}
