import Dust3DDocument
import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DKit

@MainActor
final class MeshGenerationSessionTests: XCTestCase {
    func testRetainsBoundedCacheAndReportsActualReuse() async throws {
        let session = try MeshGenerationSession()
        let initial = try await session.statistics()
        XCTAssertEqual(initial.outcome, .empty)
        XCTAssertEqual(initial.retainedPayloadBytes, 0)
        let data = try fixture("Capsule")
        let first = try await session.generateIndexed(data: data)
        let second = try await session.generateIndexed(data: data)
        XCTAssertNotNil(first.mesh)
        XCTAssertGreaterThan(first.statistics.rebuiltComponentCount, 0)
        XCTAssertEqual(first.statistics.reusedComponentCount, 0)
        XCTAssertGreaterThan(second.statistics.reusedComponentCount, 0)
        XCTAssertEqual(second.statistics.outcome, .retained)
        XCTAssertGreaterThan(second.statistics.retainedPayloadBytes, 0)
        XCTAssertLessThanOrEqual(second.statistics.retainedPayloadBytes, second.statistics.maximumCachePayloadBytes)
        XCTAssertNil(second.statistics.cacheIssue)
        assertEqualGeometry(try XCTUnwrap(second.mesh), try MeshLoader.loadIndexed(data: data))
    }

    func testResetAndDeinitDoNotInvalidateCopiedOutput() async throws {
        let data = try fixture("Capsule")
        let session = try MeshGenerationSession()
        let result = try await session.generateIndexed(data: data)
        let copied = try XCTUnwrap(result.mesh)
        let positions = copied.vertices.map(\.position)
        let indices = copied.indices
        try await session.reset()
        let reset = try await session.statistics()
        XCTAssertEqual(reset.outcome, .empty)
        XCTAssertEqual(reset.retainedPayloadBytes, 0)
        let rebuilt = try await session.generateIndexed(data: data)
        XCTAssertEqual(rebuilt.statistics.reusedComponentCount, 0)
        _ = try await session.generateIndexed(data: fixture("Sword"))
        XCTAssertEqual(copied.vertices.map(\.position), positions)
        XCTAssertEqual(copied.indices, indices)
        let independent = try await makeCopiedOutput(data)
        assertEqualGeometry(independent, copied)
    }

    func testCacheBudgetsDegradeWithoutFailingGeneration() async throws {
        let data = try fixture("Capsule")
        for budget in [0, 1, 16_384] {
            let session = try MeshGenerationSession(maximumCachePayloadBytes: budget)
            _ = try await session.generateIndexed(data: data)
            let result = try await session.generateIndexed(data: data)
            XCTAssertNotNil(result.mesh)
            XCTAssertEqual(result.statistics.retainedPayloadBytes, 0)
            XCTAssertEqual(result.statistics.reusedComponentCount, 0)
            XCTAssertEqual(result.statistics.outcome, budget == 0 ? .disabled : .bypassed)
            if budget == 0 {
                XCTAssertNil(result.statistics.cacheIssue)
            } else {
                XCTAssertEqual(result.statistics.cacheIssue?.status, 4)
                XCTAssertFalse(result.statistics.cacheIssue?.message.isEmpty ?? true)
            }
        }
    }

    func testInvalidBudgetsPreserveTypedErrors() async throws {
        for budget in [-1, Int.min, MeshGenerationSession.maximumCachePayloadBytes + 1, Int.max] {
            XCTAssertThrowsError(try MeshGenerationSession(maximumCachePayloadBytes: budget)) {
                XCTAssertEqual(($0 as? MeshLoadingError)?.status, budget < 0 ? 1 : 4)
            }
        }
        let session = try MeshGenerationSession()
        let data = try fixture("Capsule")
        for budget in [-1, Int.min, 1] {
            do {
                _ = try await session.generateIndexed(data: data, maximumPayloadBytes: budget)
                XCTFail("Invalid indexed output budgets must fail")
            } catch let error as MeshLoadingError {
                XCTAssertEqual(error.status, budget < 0 ? 1 : 4)
                XCTAssertFalse(error.message.isEmpty)
                let state = try await session.statistics()
                XCTAssertEqual(state.outcome, budget < 0 ? .empty : .retained)
            }
        }
        let valid = try await session.generateIndexed(data: data)
        XCTAssertGreaterThan(valid.statistics.reusedComponentCount, 0)
    }

    func testPrimaryFailureClearsCacheAndPreservesOriginalCause() async throws {
        let session = try MeshGenerationSession()
        let data = try fixture("Capsule")
        _ = try await session.generateIndexed(data: data)
        do {
            _ = try await session.generateIndexed(data: Data())
            XCTFail("An invalid document must fail")
        } catch let error as MeshLoadingError {
            XCTAssertEqual(error.status, 1)
            XCTAssertTrue(error.message.contains("nonempty"))
        }
        let failed = try await session.statistics()
        XCTAssertEqual(failed.outcome, .resetAfterFailure)
        XCTAssertEqual(failed.retainedPayloadBytes, 0)
        let recovered = try await session.generateIndexed(data: data)
        XCTAssertEqual(recovered.statistics.reusedComponentCount, 0)
        assertEqualGeometry(try XCTUnwrap(recovered.mesh), try MeshLoader.loadIndexed(data: data))
    }

    func testPreCancelledRequestDoesNotEnterNativeGeneration() async throws {
        let session = try MeshGenerationSession()
        let data = try fixture("Capsule")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.generateIndexed(data: data)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled requests must fail before generation")
        } catch is CancellationError {
            let state = try await session.statistics()
            XCTAssertEqual(state.outcome, .empty)
            XCTAssertEqual(state.rebuiltComponentCount, 0)
        }
    }

    func testRadiusEditsAndRestoresMatchFreshGeneration() async throws {
        let original = try Dust3DDocument(data: fixture("Capsule"))
        let node = try XCTUnwrap(original.editorContents().nodes.dropFirst().first)
        let edited = try original.applying(
            .setNode(id: node.id, position: node.value.position, radius: node.value.radius * 1.25))
        let session = try MeshGenerationSession()
        for document in [original, edited, original, edited] {
            let data = document.encoded()
            let result = try await session.generateIndexed(data: data)
            XCTAssertGreaterThan(result.statistics.rebuiltComponentCount, 0)
            assertEqualGeometry(try XCTUnwrap(result.mesh), try MeshLoader.loadIndexed(data: data))
        }
    }

    func testSuccessfulEmptyRetainsSemanticStateWithoutAFalseError() async throws {
        let xml = """
            <canvas originX='.5' originY='.5' originZ='.5'><nodes><node id='{00001000-0000-4000-8000-000000001000}'
            partId='{00000100-0000-4000-8000-000000000100}' x='.5' y='.5' z='.5' radius='.2'/></nodes><edges/>
            <parts><part id='{00000100-0000-4000-8000-000000000100}' disabled='true'/></parts><components>
            <component id='{00000200-0000-4000-8000-000000000200}' linkDataType='partId'
            linkData='{00000100-0000-4000-8000-000000000100}'/></components></canvas>
            """
        let data = try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
        let session = try MeshGenerationSession()
        for _ in 0..<2 {
            let result = try await session.generateIndexed(data: data)
            XCTAssertNil(result.mesh)
            XCTAssertEqual(result.statistics.outcome, .retained)
            XCTAssertNil(result.statistics.cacheIssue)
        }
        let restored = try await session.generateIndexed(data: fixture("Capsule"))
        XCTAssertNotNil(restored.mesh)
    }

    func testSharedAndIndependentActorsReturnIndependentCopiedValues() async throws {
        let shared = try MeshGenerationSession()
        let independent = try MeshGenerationSession()
        let capsule = try fixture("Capsule")
        let sword = try fixture("Sword")
        let expectedCapsule = try MeshLoader.loadIndexed(data: capsule)
        let expectedSword = try MeshLoader.loadIndexed(data: sword)
        let results = try await withThrowingTaskGroup(of: (MeshGenerationResult, Bool).self) { group in
            for index in 0..<8 {
                let isCapsule = index.isMultiple(of: 2)
                group.addTask {
                    let actor = isCapsule ? shared : independent
                    let result = try await actor.generateIndexed(data: isCapsule ? capsule : sword)
                    return (result, isCapsule)
                }
            }
            var results: [(MeshGenerationResult, Bool)] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(results.count, 8)
        XCTAssertTrue(results.contains { $0.0.statistics.reusedComponentCount > 0 })
        try await shared.reset()
        try await independent.reset()
        for (result, isCapsule) in results {
            assertEqualGeometry(try XCTUnwrap(result.mesh), isCapsule ? expectedCapsule : expectedSword)
        }
    }

    func testUnknownNativeOutcomeRemainsExplicit() {
        XCTAssertEqual(MeshCacheOutcome(native: Dust3DCacheOutcome(rawValue: 99)), .unknown(99))
    }

    private func makeCopiedOutput(_ data: Data) async throws -> IndexedMesh {
        let temporary = try MeshGenerationSession()
        let result = try await temporary.generateIndexed(data: data)
        return try XCTUnwrap(result.mesh)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "ds3", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func assertEqualGeometry(
        _ first: IndexedMesh, _ second: IndexedMesh, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(first.vertices.map(\.position), second.vertices.map(\.position), file: file, line: line)
        XCTAssertEqual(first.vertices.map(\.normal), second.vertices.map(\.normal), file: file, line: line)
        XCTAssertEqual(first.vertices.map(\.color), second.vertices.map(\.color), file: file, line: line)
        XCTAssertEqual(first.indices, second.indices, file: file, line: line)
        XCTAssertEqual(first.nodeCount, second.nodeCount, file: file, line: line)
        XCTAssertEqual(first.partCount, second.partCount, file: file, line: line)
        XCTAssertEqual(first.warning, second.warning, file: file, line: line)
    }
}
