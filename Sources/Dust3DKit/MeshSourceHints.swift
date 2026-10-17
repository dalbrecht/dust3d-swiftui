/// Interpretation of a quantized source association, not exact surface ownership.
public enum MeshSourceKind: Sendable, Equatable {
    /// No reliable original identity is available in the inherited association map.
    case unknown
    /// One original node is suggested by the quantized position map.
    case nodeHint
    /// Preserve the complete inherited weight list, including unresolved entries.
    case weightedHint
    /// Multiple original keys share one engine identity.
    case ambiguous
    /// A future native kind, retained without interpreting it.
    case unrecognized(UInt32)

    init(rawValue: UInt32) {
        switch rawValue {
        case 0: self = .unknown
        case 1: self = .nodeHint
        case 2: self = .weightedHint
        case 3: self = .ambiguous
        default: self = .unrecognized(rawValue)
        }
    }
}

/// Original opaque document identifiers, copied without UUID or Unicode normalization.
public struct MeshSourceIdentity: Sendable, Equatable {
    /// Exact decoded node-key bytes, represented as validated UTF-8.
    public let nodeID: String
    /// Exact original owning part key.
    public let partID: String

    /// Engine identities are byte-exact; Swift's canonical String equivalence is broader.
    /// - Parameters:
    ///   - lhs: First copied original identity.
    ///   - rhs: Second copied original identity.
    /// - Returns: True only when both node and part UTF-8 byte sequences match.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.nodeID.utf8.elementsEqual(rhs.nodeID.utf8) && lhs.partID.utf8.elementsEqual(rhs.partID.utf8)
    }
}

/// One inherited weight. Nil identity means unresolved; weights are not renormalized.
public struct MeshSourceInfluence: Sendable, Equatable {
    /// Native association interpretation, including future kinds.
    public let kind: MeshSourceKind
    /// Index into the identity table; nil preserves the native unresolved sentinel.
    public let identityIndex: Int?
    /// Original finite nonnegative value, without normalization.
    public let weight: Float
}

/// One retained triangle corner. Its ordinal matches the indexed triangle index, not a unique vertex.
public struct MeshSourceCorner: Sendable, Equatable {
    /// Interpretation of this corner's bounded influence range.
    public let kind: MeshSourceKind
    /// Safe range in the shared copied influence array.
    public let influenceRange: Range<Int>
}

/// Independent copied source hints. Position quantization and generated-ID collisions can be imprecise.
/// Example: `hints.influences[hints.corners[0].influenceRange]` reads all first-corner weights.
public struct MeshSourceHints: Sendable, Equatable {
    /// Original identity table; aliases remain separate rows.
    public let identities: [MeshSourceIdentity]
    /// One entry per retained triangle-index position.
    public let corners: [MeshSourceCorner]
    /// Full original weights referenced by corner ranges.
    public let influences: [MeshSourceInfluence]

    init(
        identities: [MeshSourceIdentity], corners: [RawMeshSourceCorner],
        influences: [RawMeshSourceInfluence], expandedVertexCount: Int
    ) throws {
        guard expandedVertexCount > 0, expandedVertexCount.isMultiple(of: 3) else {
            throw MeshSourceDataError.invalidGeometryCount
        }
        guard identities.allSatisfy({ !$0.nodeID.isEmpty && !$0.partID.isEmpty }) else {
            throw MeshSourceDataError.invalidIdentity
        }
        guard corners.count == expandedVertexCount else { throw MeshSourceDataError.invalidCornerCount }
        let copiedInfluences = try influences.map { value -> MeshSourceInfluence in
            guard value.weight.isFinite, value.weight >= 0 else { throw MeshSourceDataError.invalidWeight }
            let kind = MeshSourceKind(rawValue: value.kind)
            switch kind {
            case .nodeHint:
                guard value.sourceIndex >= 0, value.sourceIndex < identities.count else {
                    throw MeshSourceDataError.invalidInfluenceIdentity
                }
            case .unknown, .ambiguous:
                guard value.sourceIndex == -1 else { throw MeshSourceDataError.invalidInfluenceIdentity }
            case .weightedHint: throw MeshSourceDataError.invalidInfluenceKind
            case .unrecognized:
                guard value.sourceIndex == -1 || (value.sourceIndex >= 0 && value.sourceIndex < identities.count) else {
                    throw MeshSourceDataError.invalidInfluenceIdentity
                }
            }
            return MeshSourceInfluence(
                kind: kind, identityIndex: value.sourceIndex == -1 ? nil : value.sourceIndex, weight: value.weight)
        }
        let copiedCorners = try corners.map { value -> MeshSourceCorner in
            guard value.firstInfluence >= 0, value.influenceCount >= 0,
                value.firstInfluence <= copiedInfluences.count,
                value.influenceCount <= copiedInfluences.count - value.firstInfluence
            else { throw MeshSourceDataError.invalidInfluenceRange }
            let kind = MeshSourceKind(rawValue: value.kind)
            switch kind {
            case .nodeHint, .ambiguous:
                guard value.influenceCount == 1, copiedInfluences[value.firstInfluence].kind == kind else {
                    throw MeshSourceDataError.invalidCornerKind
                }
            case .unknown:
                guard
                    value.influenceCount == 0
                        || (value.influenceCount == 1 && copiedInfluences[value.firstInfluence].kind == .unknown)
                else { throw MeshSourceDataError.invalidCornerKind }
            case .weightedHint:
                guard value.influenceCount > 0 else { throw MeshSourceDataError.invalidCornerKind }
            case .unrecognized: break
            }
            return MeshSourceCorner(
                kind: kind, influenceRange: value.firstInfluence..<(value.firstInfluence + value.influenceCount))
        }
        self.identities = identities
        self.corners = copiedCorners
        self.influences = copiedInfluences
    }
}

struct RawMeshSourceCorner {
    let kind: UInt32
    let firstInfluence: Int
    let influenceCount: Int
}

struct RawMeshSourceInfluence {
    let kind: UInt32
    let sourceIndex: Int
    let weight: Float
}

enum MeshSourceDataError: Error, Equatable {
    case invalidBufferCounts
    case invalidGeometryCount
    case invalidIdentity
    case invalidCornerCount
    case invalidInfluenceRange
    case invalidInfluenceIdentity
    case invalidInfluenceKind
    case invalidWeight
    case invalidCornerKind
}
