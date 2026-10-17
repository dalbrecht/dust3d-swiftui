import XCTest

@testable import Dust3DKit

final class MeshSourceHintsTests: XCTestCase {
    private let identity = MeshSourceIdentity(nodeID: "opaque-node", partID: "opaque-part")

    func testCopiesNodeWeightedUnknownAndAmbiguousCorners() throws {
        let hints = try MeshSourceHints(
            identities: [identity],
            corners: [
                .init(kind: 1, firstInfluence: 0, influenceCount: 1),
                .init(kind: 2, firstInfluence: 0, influenceCount: 3),
                .init(kind: 3, firstInfluence: 2, influenceCount: 1),
            ],
            influences: [
                .init(kind: 1, sourceIndex: 0, weight: 0.25),
                .init(kind: 0, sourceIndex: -1, weight: 0.5),
                .init(kind: 3, sourceIndex: -1, weight: 0.25),
            ], expandedVertexCount: 3)
        XCTAssertEqual(hints.identities, [identity])
        XCTAssertEqual(hints.corners.map(\.kind), [.nodeHint, .weightedHint, .ambiguous])
        XCTAssertEqual(hints.corners[1].influenceRange, 0..<3)
        XCTAssertEqual(hints.influences.map(\.identityIndex), [0, nil, nil])
        XCTAssertEqual(hints.influences.map(\.weight), [0.25, 0.5, 0.25])
    }

    func testPreservesEmptyUnknownAndFutureKinds() throws {
        let hints = try MeshSourceHints(
            identities: [],
            corners: [
                .init(kind: 0, firstInfluence: 0, influenceCount: 0),
                .init(kind: 0, firstInfluence: 0, influenceCount: 1),
                .init(kind: 99, firstInfluence: 1, influenceCount: 1),
            ],
            influences: [.init(kind: 0, sourceIndex: -1, weight: 1), .init(kind: 88, sourceIndex: -1, weight: 0)],
            expandedVertexCount: 3)
        XCTAssertEqual(hints.corners[0].kind, .unknown)
        XCTAssertEqual(hints.corners[2].kind, .unrecognized(99))
        XCTAssertEqual(hints.influences[1].kind, .unrecognized(88))
        let future = try MeshSourceHints(
            identities: [identity],
            corners: Array(repeating: .init(kind: 77, firstInfluence: 0, influenceCount: 1), count: 3),
            influences: [.init(kind: 88, sourceIndex: 0, weight: 1)], expandedVertexCount: 3)
        XCTAssertEqual(future.influences[0].identityIndex, 0)
    }

    func testOpaqueIdentifiersUseByteExactEquality() {
        let equal = MeshSourceIdentity(nodeID: "opaque-node", partID: "opaque-part")
        XCTAssertEqual(identity, equal)
        XCTAssertNotEqual(identity, .init(nodeID: "OPAQUE-node", partID: "opaque-part"))
        XCTAssertNotEqual(identity, .init(nodeID: "opaque-node", partID: "another-part"))
        let first = "e\u{301}\u{327}"
        let second = "e\u{327}\u{301}"
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(MeshSourceIdentity(nodeID: first, partID: "part"), .init(nodeID: second, partID: "part"))
    }

    func testRejectsMalformedGeometryAndIdentityTables() {
        for count in [-1, 0, 1, 4, Int.max] {
            XCTAssertThrowsError(try make(expandedCount: count)) {
                XCTAssertEqual($0 as? MeshSourceDataError, .invalidGeometryCount)
            }
        }
        XCTAssertThrowsError(try make(corners: [])) { XCTAssertEqual($0 as? MeshSourceDataError, .invalidCornerCount) }
        for value in [MeshSourceIdentity(nodeID: "", partID: "part"), .init(nodeID: "node", partID: "")] {
            XCTAssertThrowsError(try make(identities: [value])) {
                XCTAssertEqual($0 as? MeshSourceDataError, .invalidIdentity)
            }
        }
    }

    func testRejectsOverflowingOrOutOfBoundsInfluenceRanges() {
        for corner in [
            RawMeshSourceCorner(kind: 0, firstInfluence: -1, influenceCount: 0),
            .init(kind: 0, firstInfluence: 0, influenceCount: -1),
            .init(kind: 0, firstInfluence: Int.max, influenceCount: 1),
            .init(kind: 0, firstInfluence: 0, influenceCount: Int.max),
            .init(kind: 0, firstInfluence: 1, influenceCount: 1),
        ] {
            XCTAssertThrowsError(try make(corners: Array(repeating: corner, count: 3))) {
                XCTAssertEqual($0 as? MeshSourceDataError, .invalidInfluenceRange)
            }
        }
    }

    func testRejectsInvalidInfluenceKindsIdentitiesAndWeights() {
        for value in [
            RawMeshSourceInfluence(kind: 1, sourceIndex: -1, weight: 1), .init(kind: 1, sourceIndex: 1, weight: 1),
            .init(kind: 0, sourceIndex: 0, weight: 1), .init(kind: 3, sourceIndex: 0, weight: 1),
            .init(kind: 55, sourceIndex: -2, weight: 1), .init(kind: 55, sourceIndex: Int.max, weight: 1),
        ] {
            XCTAssertThrowsError(try make(influences: [value])) {
                XCTAssertEqual($0 as? MeshSourceDataError, .invalidInfluenceIdentity)
            }
        }
        XCTAssertThrowsError(try make(influences: [.init(kind: 2, sourceIndex: 0, weight: 1)])) {
            XCTAssertEqual($0 as? MeshSourceDataError, .invalidInfluenceKind)
        }
        for weight: Float in [-1, .nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try make(influences: [.init(kind: 1, sourceIndex: 0, weight: weight)])) {
                XCTAssertEqual($0 as? MeshSourceDataError, .invalidWeight)
            }
        }
    }

    func testRejectsInconsistentCornerKinds() {
        for kind: UInt32 in [0, 2, 3] {
            let count = kind == 2 ? 0 : 1
            XCTAssertThrowsError(
                try make(
                    corners: Array(repeating: .init(kind: kind, firstInfluence: 0, influenceCount: count), count: 3))
            ) {
                XCTAssertEqual($0 as? MeshSourceDataError, .invalidCornerKind)
            }
        }
        XCTAssertThrowsError(
            try make(corners: Array(repeating: .init(kind: 1, firstInfluence: 0, influenceCount: 0), count: 3))
        ) {
            XCTAssertEqual($0 as? MeshSourceDataError, .invalidCornerKind)
        }
    }

    private func make(
        identities: [MeshSourceIdentity]? = nil, corners: [RawMeshSourceCorner]? = nil,
        influences: [RawMeshSourceInfluence]? = nil, expandedCount: Int = 3
    ) throws -> MeshSourceHints {
        try MeshSourceHints(
            identities: identities ?? [identity],
            corners: corners ?? Array(repeating: .init(kind: 1, firstInfluence: 0, influenceCount: 1), count: 3),
            influences: influences ?? [.init(kind: 1, sourceIndex: 0, weight: 1)], expandedVertexCount: expandedCount)
    }
}
