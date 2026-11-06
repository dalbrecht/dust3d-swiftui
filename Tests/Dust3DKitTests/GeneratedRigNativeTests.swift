#if MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import Foundation
    import XCTest
    @testable import Dust3DKit

    @MainActor
    final class GeneratedRigNativeTests: XCTestCase {
        nonisolated static func capsule() throws -> Data {
            try Data(
                contentsOf: XCTUnwrap(
                    Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures")))
        }

        nonisolated static func assignedCapsule() throws -> Data {
            let original = String(decoding: try capsule(), as: UTF8.self)
            guard let start = original.range(of: "<canvas") else {
                throw RigTemplateHierarchyError.invalidMetadata("fixture model")
            }
            let model = String(original[start.lowerBound...]).replacingOccurrences(
                of: "<edge ", with: "<edge boneName=\"Body\" ")
            let header = "<ds3><model name=\"model.xml\" offset=\"0\" size=\"\(model.utf8.count)\"/></ds3>"
            let prefix = "DUST3D 1.0 xml "
            let number = String(prefix.utf8.count + 11 + header.utf8.count)
            let offset = String(repeating: "0", count: 10 - number.count) + number
            return Data((prefix + offset + "\n" + header + model).utf8)
        }

        func testAssignedRigCopiesActualBonesGroundedMeshAndInfluences() async throws {
            let result = try await Task.detached {
                let hierarchy = try RigTemplateHierarchy.parse(
                    Data("<rig type='Test'><bone name='Body'/></rig>".utf8), expectedType: "Test")
                return try GeneratedRig.load(data: Self.assignedCapsule(), hierarchy: hierarchy)
            }.value
            XCTAssertEqual(result.joints.map(\.name), ["Body"])
            let joint = try XCTUnwrap(result.joints.first)
            XCTAssertNil(joint.parentIndex)
            XCTAssertEqual(abs(joint.tail.y - joint.head.y), 0.5, accuracy: 0.00001)
            XCTAssertEqual(joint.restWorld.count, 16)
            XCTAssertEqual(joint.inverseBind.count, 16)
            XCTAssertEqual(result.influences.count, result.mesh.vertices.count)
            XCTAssertTrue(result.influences.allSatisfy { $0.isBound && $0.joints.x == 0 && $0.weights.x == 1 })
            XCTAssertFalse(result.eyelidsGenerated)
            // A later independent load releases every native owner before returning.
            let before = result.mesh.vertices.map(\.position)
            _ = try await GeneratedRigService().load(data: Self.capsule(), sourceType: "Snake")
            XCTAssertEqual(result.mesh.vertices.map(\.position), before)
        }

        func testServiceUnboundNoneAndOriginalErrors() async throws {
            let service = GeneratedRigService()
            let loaded = try await service.load(data: Self.capsule(), sourceType: "Snake")
            let result = try XCTUnwrap(loaded)
            XCTAssertEqual(result.joints.count, 14)
            XCTAssertTrue(result.influences.allSatisfy { !$0.isBound && $0.joints == SIMD4(repeating: UInt32.max) })
            let none = try await service.load(data: Data(), sourceType: "None")
            XCTAssertNil(none)
            do {
                _ = try await service.load(data: Data(), sourceType: "Snake")
                XCTFail("Expected native archive error")
            } catch let error as MeshLoadingError {
                XCTAssertFalse(error.message.isEmpty)
                XCTAssertGreaterThan(error.status, 0)
            }
            do {
                _ = try await service.load(data: Data(), sourceType: "Unknown")
                XCTFail("Expected pinned resource error")
            } catch let error as RigTemplateResourceError {
                XCTAssertEqual(error, .unsupportedType("Unknown"))
            }
        }

        func testPrecancelStopsBeforeNativeLoading() async throws {
            let task = Task { try await GeneratedRigService().load(data: Self.capsule(), sourceType: "Snake") }
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("Expected cancellation")
            } catch is CancellationError {}
        }
    }
#endif
