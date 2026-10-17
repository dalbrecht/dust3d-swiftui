import Dust3DDocument
import XCTest

@testable import Dust3DKit

@MainActor
final class SourcedMeshGenerationTests: XCTestCase {
    func testCopiesSourceHintsWithCacheReuseAndIndependentLifetime() async throws {
        let data = try fixture()
        let session = try MeshGenerationSession()
        let first = try await session.generateSourcedIndexed(
            data: data, maximumSourcePayloadBytes: MeshGenerationSession.defaultSourcePayloadBytes)
        let second = try await session.generateSourcedIndexed(data: data)
        let mesh = try XCTUnwrap(second.mesh)
        let hints = try XCTUnwrap(second.sourceHints)
        XCTAssertEqual(first.statistics.reusedComponentCount, 0)
        XCTAssertGreaterThan(second.statistics.reusedComponentCount, 0)
        XCTAssertEqual(hints.corners.count, mesh.indices.count)
        XCTAssertEqual(hints.identities.count, mesh.nodeCount)
        XCTAssertTrue(hints.influences.contains { $0.kind == .nodeHint && $0.identityIndex != nil })
        XCTAssertEqual(mesh.vertices.map(\.position), try MeshLoader.loadIndexed(data: data).vertices.map(\.position))
        try await session.reset()
        _ = try await session.generateIndexed(data: data)
        let copied = try await independent(data)
        XCTAssertEqual(copied.sourceHints, hints)
        XCTAssertEqual(try XCTUnwrap(copied.mesh).indices, mesh.indices)
        XCTAssertEqual(hints, first.sourceHints)
    }

    func testSourceAndIndexedBudgetsPreserveFailureAndRecovery() async throws {
        let session = try MeshGenerationSession()
        let data = try fixture()
        for budget in [-1, Int.min, MeshGenerationSession.maximumSourcePayloadBytes + 1, Int.max] {
            do {
                _ = try await session.generateSourcedIndexed(data: data, maximumSourcePayloadBytes: budget)
                XCTFail("Invalid source budgets must reject before native conversion")
            } catch let error as MeshLoadingError {
                XCTAssertEqual(error.status, budget < 0 ? 1 : 4)
                let state = try await session.statistics()
                XCTAssertEqual(state.outcome, .empty)
            }
        }
        do {
            _ = try await session.generateSourcedIndexed(data: data, maximumPayloadBytes: -1)
            XCTFail("Negative indexed budget must reject before generation")
        } catch let error as MeshLoadingError { XCTAssertEqual(error.status, 1) }
        do {
            _ = try await session.generateSourcedIndexed(data: data, maximumSourcePayloadBytes: 1)
            XCTFail("Insufficient source budget must fail")
        } catch let error as MeshLoadingError {
            XCTAssertEqual(error.status, 4)
            XCTAssertTrue(error.message.contains("source"))
        }
        let failed = try await session.statistics()
        XCTAssertEqual(failed.outcome, .resetAfterFailure)
        let recovered = try await session.generateSourcedIndexed(data: data)
        XCTAssertEqual(recovered.statistics.reusedComponentCount, 0)
        do {
            _ = try await session.generateSourcedIndexed(data: data, maximumPayloadBytes: 1)
            XCTFail("Insufficient indexed budget must fail independently")
        } catch let error as MeshLoadingError { XCTAssertEqual(error.status, 4) }
        let retained = try await session.statistics()
        XCTAssertEqual(retained.outcome, .retained)
        let reused = try await session.generateSourcedIndexed(data: data)
        XCTAssertGreaterThan(reused.statistics.reusedComponentCount, 0)
    }

    func testCacheOnlyLimitsDoNotDiscardSourceHints() async throws {
        for budget in [0, 1] {
            let session = try MeshGenerationSession(maximumCachePayloadBytes: budget)
            let result = try await session.generateSourcedIndexed(data: fixture())
            XCTAssertNotNil(result.mesh)
            XCTAssertNotNil(result.sourceHints)
            XCTAssertEqual(result.statistics.outcome, budget == 0 ? .disabled : .bypassed)
            XCTAssertEqual(result.statistics.cacheIssue?.status, budget == 0 ? nil : 4)
        }
    }

    func testEditsRestoresAndSuccessfulEmptyKeepCurrentMetadata() async throws {
        let original = try Dust3DDocument(data: fixture())
        let node = try XCTUnwrap(original.editorContents().nodes.first)
        let edited = try original.applying(
            .setNode(id: node.id, position: node.value.position, radius: node.value.radius * 1.25))
        let session = try MeshGenerationSession()
        for document in [original, edited, original] {
            let data = document.encoded()
            let result = try await session.generateSourcedIndexed(data: data)
            let mesh = try XCTUnwrap(result.mesh)
            XCTAssertEqual(
                mesh.vertices.map(\.position), try MeshLoader.loadIndexed(data: data).vertices.map(\.position))
            XCTAssertEqual(try XCTUnwrap(result.sourceHints).corners.count, mesh.indices.count)
        }
        var disabled = original
        for part in try original.editorContents().parts {
            disabled = try disabled.applying(.setPartState(id: part.id, property: .disabled, value: true))
        }
        let empty = try await session.generateSourcedIndexed(data: disabled.encoded())
        XCTAssertNil(empty.mesh)
        XCTAssertNil(empty.sourceHints)
        XCTAssertEqual(empty.statistics.outcome, .retained)
        do {
            _ = try await session.generateSourcedIndexed(data: Data())
            XCTFail("Malformed archive must fail")
        } catch let error as MeshLoadingError { XCTAssertEqual(error.status, 1) }
    }

    func testCopiesAllWrappingWeightsAcrossCacheHits() async throws {
        // Independent MIT synthetic chain under a Cloth group.
        let xml = """
            <canvas originX='.5' originY='.5' originZ='.5'><nodes>
            <node id='{00001000-0000-4000-8000-000000001000}' partId='{00000100-0000-4000-8000-000000000100}' x='.3' y='.5' z='.5' radius='.1'/>
            <node id='{00001001-0000-4000-8000-000000001001}' partId='{00000100-0000-4000-8000-000000000100}' x='.7' y='.5' z='.5' radius='.1'/>
            </nodes><edges><edge id='{00002000-0000-4000-8000-000000002000}' partId='{00000100-0000-4000-8000-000000000100}'
            from='{00001000-0000-4000-8000-000000001000}' to='{00001001-0000-4000-8000-000000001001}'/></edges>
            <parts><part id='{00000100-0000-4000-8000-000000000100}'/></parts><components>
            <component id='{00000300-0000-4000-8000-000000000300}' wrap='Cloth' wrapFaces='64'>
            <component id='{00000200-0000-4000-8000-000000000200}' linkDataType='partId' linkData='{00000100-0000-4000-8000-000000000100}'/>
            </component></components></canvas>
            """
        let data = try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
        let session = try MeshGenerationSession()
        _ = try await session.generateSourcedIndexed(data: data)
        let result = try await session.generateSourcedIndexed(data: data)
        let hints = try XCTUnwrap(result.sourceHints)
        let corner = try XCTUnwrap(hints.corners.first { $0.kind == .weightedHint && $0.influenceRange.count > 1 })
        let weights = hints.influences[corner.influenceRange]
        XCTAssertGreaterThan(weights.count, 1)
        XCTAssertTrue(weights.allSatisfy { $0.weight.isFinite && $0.weight >= 0 })
        XCTAssertGreaterThan(result.statistics.reusedComponentCount, 0)
        XCTAssertEqual(hints.corners.count, try XCTUnwrap(result.mesh).indices.count)
    }

    func testRejectsInvalidUTF8OriginalIdentifiersWithoutRepairingThem() async throws {
        let original = try fixture()
        let document = try Dust3DDocument(data: original)
        let nodeID = try XCTUnwrap(document.editorContents().nodes.first).id
        let needle = Data(nodeID.utf8)
        var invalidBytes = Array(needle)
        let offset = try XCTUnwrap(invalidBytes.firstIndex { $0 != 123 && $0 != 125 && $0 != 45 })
        invalidBytes[offset] = 255
        var malformed = original
        var replacements = 0
        while let range = malformed.range(of: needle) {
            malformed.replaceSubrange(range, with: invalidBytes)
            replacements += 1
        }
        XCTAssertGreaterThan(replacements, 0)
        let session = try MeshGenerationSession()
        do {
            _ = try await session.generateSourcedIndexed(data: malformed)
            XCTFail("Invalid UTF-8 identities must not be silently repaired")
        } catch let error as MeshLoadingError {
            XCTAssertEqual(error.status, 3)
            XCTAssertTrue(error.message.contains("invalidIdentity"))
        }
        let valid = try await session.generateSourcedIndexed(data: original)
        XCTAssertTrue(
            try XCTUnwrap(valid.sourceHints).identities.contains { $0.nodeID.utf8.elementsEqual(nodeID.utf8) })
    }

    func testPreCancelledSourceRequestDoesNotEnterEngine() async throws {
        let session = try MeshGenerationSession()
        let data = try fixture()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.generateSourcedIndexed(data: data)
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must prevent generation")
        } catch is CancellationError {
            let state = try await session.statistics()
            XCTAssertEqual(state.outcome, .empty)
        }
    }

    private func independent(_ data: Data) async throws -> SourcedMeshGenerationResult {
        try await MeshGenerationSession().generateSourcedIndexed(data: data)
    }

    private func fixture() throws -> Data {
        try Data(
            contentsOf: XCTUnwrap(
                Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures")))
    }
}
