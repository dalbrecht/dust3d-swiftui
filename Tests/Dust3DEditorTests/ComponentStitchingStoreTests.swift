import Dust3DDocument
import Dust3DKit
import XCTest
import simd

@testable import Dust3DEditor

final class ComponentStitchingStoreTests: XCTestCase {
    private func assertFinite(_ mesh: Mesh) {
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        XCTAssertTrue(
            mesh.vertices.allSatisfy {
                $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite
                    && abs(simd_length($0.normal) - 1) < 0.0001
            })
    }
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Stitching edit or generation did not settle")
    }
    func testStraightClosedProfilesGenerateFiniteOutputAfterAngleRepair() throws {
        // Side closure joins each spline's own endpoints, not neighboring rails.
        let document = try StitchingFixture.document(loop: false, degenerateStraight: true)
        assertFinite(try MeshLoader.load(data: document.encoded()))
    }
    func testConfiguredLineClosuresAndSegmentCountsChangeFiniteGeneratedGeometry() throws {
        let original = try StitchingFixture.document(loop: false)
        let baseline = try MeshLoader.load(data: original.encoded())
        assertFinite(baseline)
        for property in ComponentStitchingClosureProperty.allCases {
            let changed = try original.applying(
                .setComponentStitchingClosure(
                    id: StitchingFixture.groupID,
                    property: property, value: property != .side))
            let mesh = try MeshLoader.load(data: changed.encoded())
            assertFinite(mesh)
            XCTAssertNotEqual(mesh.vertices.map(\.position), baseline.vertices.map(\.position), property.rawValue)
        }
        let changed = try original.applying(.setComponentTargetSegments(id: StitchingFixture.groupID, segments: 12))
        let mesh = try MeshLoader.load(data: changed.encoded())
        assertFinite(mesh)
        XCTAssertNotEqual(mesh.vertices.map(\.position), baseline.vertices.map(\.position))
    }
    func testConfiguredLoopCapDepthAndSharpnessChangeFiniteGeneratedGeometry() throws {
        let original = try StitchingFixture.document(loop: true, attributes: "backClosed='true'")
        let baseline = try MeshLoader.load(data: original.encoded())
        assertFinite(baseline)
        for property in ComponentStitchingScalarProperty.allCases {
            let changed = try original.applying(
                .setComponentStitchingScalar(
                    id: StitchingFixture.groupID,
                    property: property, value: property == .depthRatio ? 0.5 : 0.8))
            let mesh = try MeshLoader.load(data: changed.encoded())
            assertFinite(mesh)
            XCTAssertNotEqual(mesh.vertices.map(\.position), baseline.vertices.map(\.position), property.rawValue)
        }
    }
    func testConfiguredSurfacesRemainFiniteAtSupportedNumericBoundaries() throws {
        let line = try StitchingFixture.document(loop: false)
        for segments in [0, 1, 100] {
            assertFinite(
                try MeshLoader.load(
                    data: line.applying(
                        .setComponentTargetSegments(id: StitchingFixture.groupID, segments: segments)
                    ).encoded()))
        }
        let loop = try StitchingFixture.document(loop: true, attributes: "backClosed='true'")
        for property in ComponentStitchingScalarProperty.allCases {
            for value in [property.bounds.lowerBound, property.bounds.upperBound] {
                assertFinite(
                    try MeshLoader.load(
                        data: loop.applying(
                            .setComponentStitchingScalar(id: StitchingFixture.groupID, property: property, value: value)
                        ).encoded()))
            }
        }
    }
    @MainActor func testScalarDraftsAcceptLegacyCommaAndRegenerateWithExactHistory() async throws {
        let original = try StitchingFixture.document(loop: true, attributes: "backClosed='true'")
        for property in ComponentStitchingScalarProperty.allCases {
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: original.encoded())
            try await settle(store)
            let baseline = try XCTUnwrap(store.mesh)
            store.selectComponent(StitchingFixture.groupID)
            try await settle(store)
            store.setComponentStitchingScalar(
                StitchingFixture.groupID, property: property,
                value: property == .depthRatio ? "0,5" : "0,8")
            try await settle(store)
            XCTAssertNil(store.errorMessage)
            let changed = try XCTUnwrap(store.snapshot?.document.encoded())
            let mesh = try XCTUnwrap(store.mesh)
            assertFinite(mesh)
            XCTAssertNotEqual(mesh.vertices.map(\.position), baseline.vertices.map(\.position))
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
            let revision = store.previewRevision
            store.setComponentStitchingScalar(
                StitchingFixture.groupID, property: property,
                value: String(property.defaultValue))
            try await settle(store)
            XCTAssertEqual(store.previewRevision, revision)
            XCTAssertTrue(store.canRedo)
            store.redo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), changed)
            XCTAssertEqual(store.mesh?.vertices.map(\.position), mesh.vertices.map(\.position))
        }
    }
    @MainActor func testStorePreservesSelectionCameraArchiveHistoryAndRejectsInvalidDrafts() async throws {
        let original = try StitchingFixture.document(loop: false)
        let store = EditorStore()
        defer { store.stop() }
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        await store.load(data: original.encoded())
        try await settle(store)
        let baseline = try XCTUnwrap(store.mesh)
        store.selectComponent(StitchingFixture.groupID)
        try await settle(store)
        let camera = store.cameraReset
        let revision = store.previewRevision
        for text in ["", "future", "1.5", "-1", "101", "1e1"] {
            store.setComponentTargetSegments(StitchingFixture.groupID, segments: text)
            try await settle(store)
            XCTAssertTrue(store.errorMessage?.contains("0 to 100") == true)
        }
        for property in ComponentStitchingScalarProperty.allCases {
            for text in ["", "future", "nan", "inf", "-0.1", "2.1", "1e-50", "1e-999"] {
                store.setComponentStitchingScalar(StitchingFixture.groupID, property: property, value: text)
                try await settle(store)
                XCTAssertNotNil(store.errorMessage)
            }
        }
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(store.previewRevision, revision)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        store.setComponentStitchingClosure(StitchingFixture.groupID, property: .front, value: true)
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        let mesh = try XCTUnwrap(store.mesh)
        assertFinite(mesh)
        XCTAssertNotEqual(mesh.vertices.map(\.position), baseline.vertices.map(\.position))
        XCTAssertEqual(store.snapshot?.selectedComponentID, StitchingFixture.groupID)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(publications, 1)
        let changed = try XCTUnwrap(store.snapshot?.document.encoded())
        XCTAssertEqual(
            try Dust3DDocument(data: changed).asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        store.setComponentStitchingClosure(StitchingFixture.groupID, property: .front, value: false)
        try await settle(store)
        XCTAssertTrue(store.canRedo)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), changed)
        XCTAssertEqual(store.mesh?.vertices.map(\.position), mesh.vertices.map(\.position))
        store.setComponentTargetSegments(StitchingFixture.groupID, segments: "12")
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.selectedComponent?.stitching.targetSegments, 12)
    }
}
