import Dust3DDocument
import XCTest

@testable import Dust3DKit

/// Reuses the pinned core's existing static catalog smoke contract; no document or frames are generated.
@MainActor
final class NativeAnimationCatalogIntegrationTests: XCTestCase {
    func testExistingStaticCatalogOwnsMetadataAfterNativeOwnerReleaseAndSubsequentLoad() async throws {
        let loader = NativeAnimationCatalogLoader()
        let catalog = try await loader.load()
        XCTAssertEqual(catalog.clips.count, 180)
        XCTAssertEqual(catalog.clips.filter(\.isLegacyAlias).count, 4)
        XCTAssertEqual(Set(catalog.clips.map(\.rig)).count, 7)
        XCTAssertEqual(catalog.clips.reduce(0) { $0 + $1.controls.count }, 1592)
        let sprint = try XCTUnwrap(catalog.clip(type: "BipedSprint"))
        XCTAssertEqual(sprint.seconds, 0.65)
        XCTAssertEqual(sprint.samples, 32)
        XCTAssertTrue(sprint.loops)
        let wing = try XCTUnwrap(catalog.clip(type: "BirdGlide")?.controls.first { $0.name == "wingSpreadAngle" })
        XCTAssertEqual(wing.defaultParameter, 0.15)
        XCTAssertEqual(wing.defaultSlider, 100)
        XCTAssertEqual(wing.divisor, 667)
        XCTAssertEqual(try wing.value(at: 100), 100.0 / 667.0)
        XCTAssertEqual(catalog.surfaceMaterials, ["Stone", "Wood", "Sand", "Metal", "Grass", "Water", "Dirt", "Snow"])
        XCTAssertEqual(catalog.timing.minimumSeconds, 0.01)
        XCTAssertEqual(catalog.timing.maximumSeconds, 59.99)
        XCTAssertEqual(catalog.timing.minimumFrames, 1)
        XCTAssertEqual(catalog.timing.maximumFrames, 4999)
        let retainedTypes = catalog.clips.map { Array($0.type.utf8) }
        let retainedLabels = catalog.clips.flatMap(\.controls).map { Array($0.label.utf8) }
        _ = try await loader.load()
        XCTAssertEqual(catalog.clips.map { Array($0.type.utf8) }, retainedTypes)
        XCTAssertEqual(catalog.clips.flatMap(\.controls).map { Array($0.label.utf8) }, retainedLabels)
    }
}
