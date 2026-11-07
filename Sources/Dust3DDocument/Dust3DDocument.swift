import Foundation

/// Failures at the archive and editable-node boundary. Invalid commands never change a document.
public enum DocumentError: Error, Equatable, Sendable {
    case invalidArchive
    case invalidXML
    case invalidReferenceImage
    case invalidOrigin
    case limitExceeded
    case missingNode(String)
    case missingPart(String)
    case invalidComponent
    case invalidComponentStructure
    case invalidComponentWrapping
    case invalidComponentWrapBinding
    case invalidComponentTargetSegments
    case invalidComponentStitchingScalar
    case invalidComponentSmoothing
    case invalidComponentName
    case invalidComponentColor
    case missingComponent(String)
    case invalidPartCutFace
    case invalidPartCutRotation
    case invalidPartHollowThickness
    case invalidPartMirrorRole
    case invalidPartMirrorOrigin
    case invalidPartDeformation
    case invalidPartMaterial
    case invalidPartName
    case invalidBoneName
    case invalidNode
    case invalidNodeDeformation
    case cyclicProfile
    case conflictingAsset(String)
    case transactionAlreadyOpen
    case noTransaction
}

public struct NodePosition: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct EditableNode: Equatable, Sendable {
    public let position: NodePosition
    public let radius: Double

    public init(position: NodePosition, radius: Double) {
        self.position = position
        self.radius = radius
    }
    /// Geometry values accepted by the document and native-engine boundaries.
    public var isValid: Bool {
        radius >= 0 && [position.x, position.y, position.z, radius].allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
    }

}

/// One geometry replacement in a bulk update. Identity and unrelated XML stay unchanged.
public struct NodeUpdate: Sendable {
    public let id: String
    public let value: EditableNode
    public init(id: String, value: EditableNode) {
        self.id = id
        self.value = value
    }
}

/// Atomic document commands. Unknown archive data remains untouched.
public enum DocumentCommand: Sendable {
    /// Create stored intent with a fresh caller-supplied ID and name/type at most 1024 UTF-8 bytes.
    /// Throws typed animation errors for invalid/duplicate metadata or DocumentError for quotas; no clip is evaluated.
    /// Example: `.createAnimation(id: freshID, name: "Walk", type: "walk")`.
    case createAnimation(id: String, name: String, type: String)
    /// Rename stored intent, preserving unknown data and exact no-ops; empty names are allowed.
    /// `id` is exact source identity; `name` is at most 1024 UTF-8 bytes without controls/newlines.
    /// Throws typed animation errors. Example: `.setAnimationName(id: id, name: "Rest")`.
    case setAnimationName(id: String, name: String)
    /// Store a nonempty type (at most 1024 UTF-8 bytes), without catalog evaluation or parameter resets.
    /// Throws typed animation errors. Example: `.setAnimationType(id: id, type: "walk")`.
    case setAnimationType(id: String, type: String)
    /// Set/remove one unqualified parameter; nil removes it. No timing is evaluated.
    /// `name` is at most 128 ASCII identifier bytes; id/name/type/xmlns are reserved.
    /// `value` is at most 4096 UTF-8 bytes without controls/newlines; unknown values remain stored intent.
    /// Throws typed animation errors. Example: `.setAnimationParameter(id: id, name: "duration", value: "1.0")`.
    case setAnimationParameter(id: String, name: String, value: String?)
    /// Clone complete stored intent including nested data; supply a fresh ID and bounded display name.
    /// Throws typed animation/metadata quota errors; assets stay shared and unchanged.
    /// Example: `.duplicateAnimation(id: id, newID: freshID, name: "Walk copy")`.
    case duplicateAnimation(id: String, newID: String, name: String)
    /// Remove one exact `id`, retaining unrelated metadata and assets. Throws a typed missing/identity error.
    /// Example: `.deleteAnimation(id: id)`; ordinary document history supplies Undo/Redo.
    case deleteAnimation(id: String)
    /// Set an editable edge's exact inherited bone identity; empty clears the attribute.
    /// - Parameters: `id` is the edge identity; `name` is at most 1024 UTF-8 bytes without controls/newlines.
    /// - Throws: `invalidBoneName` or `invalidNode` for missing/read-only endpoints; no generation occurs.
    /// - Example: `.setEdgeBoneName(id: edgeID, name: "Root")`.
    case setEdgeBoneName(id: String, name: String)
    /// Assign one exact name to explicit edges in one owned XML traversal; empty clears their attributes.
    /// - Parameters: `ids` are exact edge identities; `name` follows the single-edge byte/control limits.
    /// - Throws: Original `invalidBoneName` or `invalidNode`; all edges are preflighted before changes.
    /// - Example: `.setEdgeBoneNames(ids: [firstEdge, secondEdge], name: "Root")`.
    case setEdgeBoneNames(ids: Set<String>, name: String)
    /// Clear stored rig metadata on exact edge IDs across the document, including read-only parts.
    /// This explicit global rig action does not broaden ordinary editable-edge assignment.
    /// - Throws: `invalidNode` if any requested edge is absent; no partial mutation is published.
    /// - Example: `.clearEdgeBoneNames(ids: matchingEdges)`.
    case clearEdgeBoneNames(ids: Set<String>)
    /// Store a recognized rig template without generating or replacing any skeleton data.
    /// Semantic no-ops preserve source bytes. Example: `.setRigType(.biped)`.
    case setRigType(DocumentRigType)
    /// Store inherited eyelid intent without evaluating a rig. False removes the attribute on change.
    /// Example: `.setHeadHasEyelids(true)`; unrelated and unsupported rig data remains retained.
    case setHeadHasEyelids(Bool)
    /// Set finite canvas origin coordinates within ±1,000,000 without moving any nodes.
    case setOrigin(NodePosition)
    /// Store finite hollow thickness in 0...1; both endpoints are solid in the reviewed local core.
    /// Zero removes the attribute on change; semantic no-ops retain exact archive bytes.
    /// Geometry requires the separately reviewed core; the production pin retains this as unsupported metadata.
    /// Throws `invalidPartHollowThickness` or `missingPart`. Example: `.setPartHollowThickness(id: id, thickness: 0.5)`.
    case setPartHollowThickness(id: String, thickness: Double)
    /// Rename the legacy part name, preserving component names. Empty input restores the default label.
    case setPartName(id: String, name: String)
    /// Rename one component independently of its linked part; empty input removes its name.
    case setComponentName(id: String, name: String)
    /// Replace the final equipment suffix on a linked Model component. Blank input removes it.
    /// The exact component ID selects the owner; the trimmed slot is stored as entered, for example `armor/2`.
    case setComponentEquipmentSlot(id: String, slot: String)
    /// Set or remove one explicit component color without changing descendants or unknown metadata.
    /// - Parameters: `id` is the exact component identity; `color` is bounded channels or nil to remove.
    /// Throws `missingComponent` for an absent identity; semantic no-ops retain original archive bytes.
    /// Example: `.setComponentColor(id: id, color: DocumentColor(red: 255, green: 0, blue: 0))`.
    case setComponentColor(id: String, color: DocumentColor?)
    /// Atomically replace/remove explicit colors with one indexed DOM update and serialization.
    /// - Parameter updates: At most `DocumentComponentColorUpdate.maximumBatchCount` unique component identities.
    /// - Throws: `invalidComponentColor` for duplicate updates, `missingComponent` for missing targets,
    ///   existing hierarchy/graph errors or `limitExceeded`; no partial document is published.
    /// Semantic no-ops and an empty batch preserve every original archive byte.
    /// Example: `.setComponentColors([.init(componentID: id, color: nil)])`.
    case setComponentColors([DocumentComponentColorUpdate])
    /// Assign a retained image or remove an override; unreferenced/shared assets remain untouched.
    /// Throws `TextureImageReferenceError` for unresolved resources, or `missingComponent`.
    /// Example: `.setComponentColorImage(id: componentID, imageID: nil)` removes the override.
    case setComponentColorImage(id: String, imageID: String?)
    /// Atomically insert bounded PNG bytes and assign their image identity, preserving unrelated assets.
    /// Existing identical bytes can be shared; conflicting identities throw without publication.
    /// Throws `PNGContainerError`, `TextureImageReferenceError` or `DocumentError`.
    /// Pixel/CRC validation is a platform import responsibility; this validates the PNG envelope.
    /// Example: `.importComponentColorImage(id: componentID, imageID: freshID, png: bytes)`.
    case importComponentColorImage(id: String, imageID: String, png: Data)
    /// Assign or clear one retained image on unique exact component identities in one archive update.
    case setComponentColorImages(ids: [String], imageID: String?)
    /// Append one PNG and assign its identity to all captured components in one archive update.
    case importComponentColorImages(ids: [String], imageID: String, png: Data)
    /// Replace one mesh setting across literal component IDs in one indexed transaction.
    /// All roles and links are eligible. Invalid IDs or cutoff reject atomically. Empty arrays are no-ops.
    case editComponentMeshSettings(ids: [String], edit: ComponentMeshEdit)
    /// Set one component combination mode, clearing legacy component inversion on a semantic change.
    /// Unknown unrelated XML/assets stay intact; semantic no-ops preserve original archive bytes.
    case setComponentCombineMode(id: String, mode: ComponentCombineMode)
    /// Set finite normal smoothing cutoff within 0–180 degrees; zero removes the source attribute.
    /// A semantic no-op retains original spellings/bytes; invalid values throw `invalidComponentSmoothing`.
    case setComponentSmoothCutoffDegrees(id: String, degrees: Double)
    /// Set a group wrapping mode without resetting explicit parameters. Throws missingComponent/invalidComponentWrapping.
    /// Example: `.setComponentWrapMode(id: groupID, mode: .cloth)`.
    case setComponentWrapMode(id: String, mode: ComponentWrapMode)
    /// Atomically replace one field on all explicitly selected groups without expanding descendants.
    /// Throws missingComponent, invalidComponentWrapping or limitExceeded before mutation.
    /// Example: `.editComponentWrapping(ids: groupIDs, edit: .mode(.cloth))`.
    case editComponentWrapping(ids: [String], edit: ComponentWrappingEdit)
    /// Replace only a group's body-weight reference with an eligible group or Own Children.
    /// Throws missingComponent/invalidComponentWrapping/invalidComponentWrapBinding atomically.
    /// Example: `.setComponentWrapBinding(id: garmentID, choice: .group(bodyID))`.
    case setComponentWrapBinding(id: String, choice: ComponentWrapBindingChoice)
    /// Replace one group pattern; None removes only wrapPattern. Throws missingComponent/invalidComponentWrapping.
    /// Example: `.setComponentSurfacePattern(id: groupID, pattern: .spots)`.
    case setComponentSurfacePattern(id: String, pattern: ComponentSurfacePattern)
    /// Replace a finite finish scalar within its Qt editing range, retaining unrelated source fields.
    /// Throws missingComponent/invalidComponentWrapping. Example: `.setComponentSurfaceScalar(id: id, property: .wrinkles, value: 0.5)`.
    case setComponentSurfaceScalar(id: String, property: ComponentSurfaceScalar, value: Double)
    /// Assign opaque pattern RGB or nil for automatic ink; other metadata/assets remain untouched.
    /// Throws missingComponent/invalidComponentWrapping. Example: `.setComponentSurfaceColor(id: id, color: nil)`.
    case setComponentSurfaceColor(id: String, color: DocumentColor?)
    /// Set a group wrapping scalar within its property bounds. Throws invalidComponentWrapping/missingComponent.
    /// Example: `.setComponentWrapScalar(id: groupID, property: .offset, value: 0.01)`.
    case setComponentWrapScalar(id: String, property: ComponentWrappingScalarProperty, value: Double)
    /// Set whether wrapping retains its children. Throws missingComponent/invalidComponentWrapping for non-groups.
    /// Example: `.setComponentWrapKeepChildren(id: groupID, value: true)`.
    case setComponentWrapKeepChildren(id: String, value: Bool)
    /// Set a whole face count in 64...20000. Throws invalidComponentWrapping/missingComponent.
    /// Example: `.setComponentWrapFaces(id: groupID, faces: 1200)`.
    case setComponentWrapFaces(id: String, faces: Int)
    /// Set one stitching closure flag; false restores the absent default. Throws `missingComponent`.
    /// Example: `.setComponentStitchingClosure(id: id, property: .front, value: true)`.
    case setComponentStitchingClosure(id: String, property: ComponentStitchingClosureProperty, value: Bool)
    /// Set a bounded loop-cap parameter. Throws `invalidComponentStitchingScalar` or `missingComponent`.
    /// Example: `.setComponentStitchingScalar(id: id, property: .depthRatio, value: 0.5)`.
    case setComponentStitchingScalar(id: String, property: ComponentStitchingScalarProperty, value: Double)
    /// Set target segments in 0...100; zero means automatic. Throws `invalidComponentTargetSegments` or `missingComponent`.
    /// Example: `.setComponentTargetSegments(id: id, segments: 12)`.
    case setComponentTargetSegments(id: String, segments: Int)
    /// Move a component within its current siblings, preserving its entire subtree and all assets.
    case placeComponents(ids: [String], placement: ComponentDropPlacement)
    case reorderComponent(id: String, direction: ComponentOrderMove)
    /// Wrap nonempty, unique siblings in a fresh unlinked group, retaining their source order.
    case groupComponents(ids: [String], groupID: String)
    /// Ungroup every explicit eligible wrapper in one atomic indexed transaction; selected leaves are no-ops.
    /// Loaded linked/opaque wrappers with component children are supported. XML-context changes may reject.
    case ungroupComponents(ids: [String])
    /// Remove an unlinked nonempty group and its settings, promoting all child XML at its position.
    case ungroupComponent(id: String)
    /// Append one subtree to an unlinked group or to the document root; cycles reject atomically.
    case reparentComponent(id: String, parentID: String?)
    /// Append selected subtree roots in document order as one atomic move.
    case reparentComponents(ids: [String], parentID: String?)
    /// Change one procedural part flag, preserving all other metadata, source graph and assets.
    /// Part locks constrain node editing; modifier metadata remains editable as in the inherited app.
    case setPartModifier(id: String, property: PartModifierProperty, value: Bool)
    /// Set the exact part’s mirror flag. Enabling initializes an absent origin or rejects an invalid authored origin.
    case setPartXMirrored(id: String, value: Bool)
    /// Set a finite width/thickness scale in 0...2 that does not overflow or underflow in the engine Float; one restores the absent default.
    /// Throws `invalidPartDeformation` for invalid scales or `missingPart` for absent identities.
    /// Example: `.setPartDeformationScale(id: id, property: .width, value: 0.995)`.
    case setPartDeformationScale(id: String, property: PartDeformationProperty, value: Double)
    /// Toggle maximum-radius deformation without changing scale values, nodes or unrelated metadata.
    /// Throws `missingPart` for absent identities. Example: `.setPartDeformationUnified(id: id, value: true)`.
    case setPartDeformationUnified(id: String, value: Bool)
    /// Select a preset or link to a profile; newly changed targets must exist.
    /// Throws `missingPart`, `invalidPartCutFace` or `cyclicProfile` for invalid changes.
    /// Reapplying an unchanged unresolved imported link preserves bytes and redo.
    /// Example: `.setPartCutFace(id: id, selection: .preset(.triangle))`.
    case setPartCutFace(id: String, selection: CutFaceSelection)
    /// Set one existing material scalar within its reference editor range.
    /// Throws `invalidPartMaterial` for invalid values or `missingPart` for an absent identity.
    /// Semantic no-ops preserve original bytes; defaults remove the field on a genuine change.
    /// Example: `.setPartMaterial(id: id, property: .metallic, value: 0.5)`.
    case setPartMaterial(id: String, property: PartMaterialProperty, value: Double)
    /// Set a finite half-turn rotation in -1...1 that does not overflow or underflow in the engine Float; zero restores the absent default.
    /// Throws `invalidPartCutRotation` or `missingPart`. Example: `.setPartCutRotation(id: id, rotation: 0.25)`.
    case setPartCutRotation(id: String, rotation: Double)
    /// Fill isolated closed stitching-loop interiors without changing graph nodes or other part metadata.
    /// False restores the absent default; semantic no-ops retain source spelling and redo. Throws `missingPart`.
    /// Example: `.setPartFillLoopInterior(id: id, value: true)`.
    case setPartFillLoopInterior(id: String, value: Bool)
    /// Change a procedural role without moving nodes, unlocking parts or rewriting unrelated metadata.
    /// Throws `missingPart` for an absent identity. Unsupported source roles survive until explicit replacement.
    /// Example: `.setPartTarget(id: id, target: .cutFace)`.
    case setPartTarget(id: String, target: PartTarget)
    /// Assign explicit component-owned part roles and atomically group root stitching siblings when needed.
    case setComponentPartRoles(componentIDs: [String], target: PartTarget, newGroupID: String?)
    /// Change a part flag, including restoring a hidden/locked/disabled part.
    case setPartState(id: String, property: PartStateProperty, value: Bool)
    /// Set one flag on bounded, literal UTF-8 part IDs and publish the result as one document edit.
    case setPartsState(ids: [String], property: PartStateProperty, value: Bool)
    /// Replace Qt's canvas.png asset with PNG-signature bytes (at most 32 MiB), or remove it with nil.
    /// Full raster decoding/validation belongs at the platform import boundary.
    case setReferenceImagePNG(Data?)
    case setNode(id: String, position: NodePosition, radius: Double)
    case setNodes([NodeUpdate])
    /// Replace one taper scale on an editable Model node. A value of 1 restores the inherited default.
    /// The value must be finite, positive, at most 1,000,000, and nonzero in the engine's Float representation.
    case setNodeDeformationScale(id: String, property: PartDeformationProperty, value: Double)
    case addNode(id: String, partID: String, componentID: String?, position: NodePosition, radius: Double)
    case addEdge(id: String, from: String, to: String)
    /// Atomically split an editable edge at the average endpoint position and radius.
    /// - Parameters: `id` retains the first segment; `nodeID` and `edgeID` are fresh identities (1...128 UTF-8 bytes).
    /// - Throws: `invalidNode` for invalid identities, geometry or ownership; `limitExceeded` for graph bounds.
    /// - Example: `.insertEdgeMidpoint(id: "edge", nodeID: "middle", edgeID: "second")`.
    case insertEdgeMidpoint(id: String, nodeID: String, edgeID: String)
    /// Atomically split a captured explicit edge batch in Qt UUID order using one graph/XML index.
    /// - Parameter insertions: One unique original edge and two fresh identities per split.
    /// - Throws: `invalidNode` for invalid/duplicate/readonly requests or `limitExceeded` for aggregate graph quotas.
    /// - Example: `.insertEdgeMidpoints([.init(originalEdgeID: "edge", nodeID: "mid", edgeID: "tail")])`.
    case insertEdgeMidpoints([EdgeMidpointInsertion])
    case joinNodes(id: String, from: String, to: String)
    /// Reduce selected degree-two nodes sequentially in Qt UUID order, retaining the first live incident edge.
    /// - Parameter ids: Selected node identities; absent nodes and degrees other than two are skipped.
    /// - Throws: `invalidNode` for unsafe ownership/topology/read-only candidates; `limitExceeded` above 10,000 selections.
    /// - Example: `.reduceNodes([firstNodeID, secondNodeID])` creates one atomic history edit.
    case reduceNodes([String])
    /// Delete explicit XML subtrees and graph parts only when no known component reference survives.
    /// Opaque links, incoming profile/wrapping references, assets and unrelated metadata are retained.
    /// Throws missingComponent, invalidComponentStructure or limitExceeded atomically.
    /// Example: `.removeComponentSubtrees([groupID, leafID])` uses one undo step.
    case removeComponentSubtrees([String])
    case removeNode(id: String)
    case removeNodes([String])
    /// Remove explicitly empty editable parts and their references; retain nested content and all assets.
    case pruneEmptyParts([String])
    case removeEdge(id: String)
    /// Remove one captured edge set atomically with one XML traversal and retained node identities.
    /// - Parameter ids: At most 20,000 unique existing edges whose endpoints are editable.
    /// - Throws: `invalidNode` for missing, duplicate or read-only edges; `limitExceeded` above the count bound.
    /// - Example: `.removeEdges(["first", "second"])` is one undoable edit.
    case removeEdges([String])
    case reverseEdges([String])
    case splitPart(id: String, identities: [PartSplitIdentity])
    case pasteNodes(
        clipboard: NodeClipboard, identities: [String: String], offset: NodePosition,
        partitions: [String: [PartSplitIdentity]] = [:])
}

/// Stable node metadata for editor presentation. Geometry and unknown XML remain in the archive.
public struct DocumentNode: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let partID: String?
    public let value: EditableNode
    public let isVisible: Bool
    public let isEditable: Bool

    fileprivate let deformation: NodeDeformation

    /// The saved taper scale, 1 when absent or nil when the stored value is unsupported.
    public func deformationScale(_ property: PartDeformationProperty) -> Double? {
        deformation.scale(property)
    }
}

public struct DocumentEdge: Identifiable, Equatable, Sendable {
    public let id: String
    public let fromID: String
    public let toID: String
    /// Exact stored edge owner, nil when absent; never inferred from either endpoint's part.
    public let partID: String?
    /// Exact retained bone lookup intent, empty when unassigned; not proof of a generated bone or weight.
    public let boneName: String

    /// Construct an edge snapshot. Omitting the optional owner preserves source compatibility for legacy callers.
    /// - Parameters: `id`, `fromID` and `toID` retain graph identities; `boneName` retains lookup spelling; `partID` is the stored owner.
    /// - Example: `DocumentEdge(id: "edge", fromID: "a", toID: "b", partID: "part")`.
    public init(id: String, fromID: String, toID: String, boneName: String = "", partID: String? = nil) {
        self.id = id
        self.fromID = fromID
        self.toID = toID
        self.boneName = boneName
        self.partID = partID
    }

    /// Compare the exact UTF-8 lookup spelling used by the inherited rig generator.
    /// - Parameter name: Candidate stored bone identity, including case and spacing.
    /// - Returns: Whether its UTF-8 bytes equal the retained name.
    /// - Example: `edge.hasExactBoneName("Root")`.
    public func hasExactBoneName(_ name: String) -> Bool {
        BoneNameIdentity(boneName) == BoneNameIdentity(name)
    }

    /// Compare edge snapshots while retaining byte-distinct bone lookup identities.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.fromID == rhs.fromID && lhs.toID == rhs.toID && lhs.partID == rhs.partID
            && lhs.hasExactBoneName(rhs.boneName)
    }
}

public struct DocumentContents: Sendable {
    public let nodes: [DocumentNode]
    public let edges: [DocumentEdge]
    public let parts: [DocumentPart]
    /// Complete supported stored origin; nil preserves missing/unsupported source fields.
    public let origin: NodePosition?
    /// Stored rig intent decoded with the graph, without native evaluation or a second XML parse.
    public let rigSettings: DocumentRigSettings

    init(
        nodes: [DocumentNode], edges: [DocumentEdge], parts: [DocumentPart] = [], origin: NodePosition? = nil,
        rigSettings: DocumentRigSettings = .init(root: nil)
    ) {
        self.nodes = nodes
        self.edges = edges
        self.parts = parts
        self.origin = origin
        self.rigSettings = rigSettings
    }
}

package struct ReplayProperty: Equatable, Sendable {
    package enum Owner: Hashable, Sendable { case node, part, component, animation }
    package let owner: Owner
    package let id: String
    package let attributes: [String]
    package let title: String
    package let profilePartID: String?

    package init(owner: Owner, id: String, attributes: [String], title: String, profilePartID: String?) {
        self.owner = owner
        self.id = id
        self.attributes = attributes
        self.title = title
        self.profilePartID = profilePartID
    }
}

/// Immutable archive value. Unchanged saves retain every input byte, including unknown assets.
public struct Dust3DDocument: Sendable {
    private struct Item: Sendable {
        let name: String
        let type: String
        let range: Range<Int>
    }

    private let bytes: Data
    private let header: Data
    private let payloadOffset: Int
    private let items: [Item]
    private let modelIndex: Int
    private var graphOrder: DocumentGraphOrder

    /// Decode a bounded .ds3 archive without generating geometry or interpreting unknown fields.
    /// Throws DocumentError for malformed, ambiguous, external-entity or oversized inputs.
    public init(data: Data) throws {
        guard data.count <= 256 * 1024 * 1024 else { throw DocumentError.limitExceeded }
        let bytes = Data(data)
        guard let lineEnd = bytes.prefix(1024).firstIndex(of: 10) else {
            throw DocumentError.invalidArchive
        }
        var line = Data(bytes[..<lineEnd])
        if line.starts(with: [0xd3, 0x3d]) { line.removeFirst(2) }
        guard let firstLine = String(data: line, encoding: .utf8) else {
            throw DocumentError.invalidArchive
        }
        let tokens = firstLine.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count == 4, tokens[0] == "DUST3D", tokens[1] == "1.0", tokens[2] == "xml",
            let offset = Self.unsigned(String(tokens[3])), offset > lineEnd, offset <= bytes.count,
            offset - lineEnd - 1 <= 1024 * 1024
        else { throw DocumentError.invalidArchive }
        let header = Data(bytes[(lineEnd + 1)..<offset])
        let xml = try Self.xml(header, root: "ds3")
        var items: [Item] = []
        var names = Set<String>()
        for child in xml.rootElement()?.children ?? [] where child.kind == .element {
            guard let element = child as? XMLElement,
                let name = element.attribute(forName: "name")?.stringValue?.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                !name.isEmpty, names.insert(name).inserted,
                let start = Self.unsigned(element.attribute(forName: "offset")?.stringValue),
                let size = Self.unsigned(element.attribute(forName: "size")?.stringValue),
                start <= bytes.count - offset, size <= bytes.count - offset - start,
                let type = element.name
            else { throw DocumentError.invalidArchive }
            items.append(Item(name: name, type: type, range: start..<(start + size)))
        }
        guard items.count <= 10_000 else { throw DocumentError.limitExceeded }
        let ordered = items.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var end = 0
        for item in ordered {
            if item.range.isEmpty { continue }
            guard item.range.lowerBound >= end else { throw DocumentError.invalidArchive }
            end = item.range.upperBound
        }
        let models = items.indices.filter { items[$0].type == "model" }
        guard models.count == 1, let modelIndex = models.first else { throw DocumentError.invalidArchive }
        let range = items[modelIndex].range
        guard range.count <= 16 * 1024 * 1024 else { throw DocumentError.limitExceeded }
        let model = try Self.xml(Data(bytes[(offset + range.lowerBound)..<(offset + range.upperBound)]), root: "canvas")
        var nodeIDs = Set<String>()
        for node in try Self.nodes(model) {
            guard let id = node.attribute(forName: "id")?.stringValue, !id.isEmpty,
                nodeIDs.insert(id).inserted
            else { throw DocumentError.invalidNode }
        }
        self.bytes = bytes
        self.header = header
        self.payloadOffset = offset
        self.items = items
        self.modelIndex = modelIndex
        self.graphOrder = DocumentGraphOrder(model: model)
    }

    /// Wrap a Qt canvas snapshot in an asset-free archive using the existing bounded XML validator.
    /// - Parameter snapshotXML: UTF-8 canvas XML, at most 16 MiB; unknown fields are retained verbatim.
    /// - Throws: Typed document errors for malformed XML, excessive depth/size or invalid editable graph data.
    /// - Note: Plain XML cannot carry embedded archive assets. Use the archive initializer for lossless asset transfer.
    /// See the document README for clipboard integration examples.
    public init(snapshotXML: Data) throws {
        guard snapshotXML.count <= 16 * 1024 * 1024 else { throw DocumentError.limitExceeded }
        self = try Dust3DDocument(data: Self.emptyArchive()).replacingModel(Data(snapshotXML))
        graphOrder = DocumentGraphOrder(model: try Self.xml(modelXML, root: "canvas"))
        _ = try editorContents()
    }

    /// Original or edited model XML; unknown elements and attributes are retained.
    public var modelXML: Data {
        let range = items[modelIndex].range
        return Data(bytes[(payloadOffset + range.lowerBound)..<(payloadOffset + range.upperBound)])
    }

    /// Return archive bytes ready for an atomic file write. No-op saves are byte-identical.
    public func encoded() -> Data { bytes }

    /// Read inherited canvas rig parameters without invoking native generation.
    /// - Returns: Recognized or unsupported source intent and inherited eyelid state.
    /// - Throws: `DocumentError.invalidXML` for malformed canvas XML.
    /// - Example: `let template = try document.rigSettings().rigType`.
    public func rigSettings() throws -> DocumentRigSettings {
        let model = try Self.xml(modelXML, root: "canvas")
        guard let root = model.rootElement() else { throw DocumentError.invalidXML }
        return DocumentRigSettings(root: root)
    }

    /// Read stored animation metadata without evaluating clips, rigs or audio.
    /// - Parameter maximumCount: Metadata row/extension-element bound in 0...10,000.
    /// - Returns: Source-ordered records, preserving unsupported types and missing name/type fields.
    /// - Throws: Typed animation metadata errors, XML errors or `limitExceeded`; source bytes stay unchanged.
    /// - Example: `try document.animations().first?.parameter(named: "duration")`.
    public func animations(maximumCount: Int = 10_000) throws -> [DocumentAnimation] {
        guard (0...10_000).contains(maximumCount) else { throw DocumentError.limitExceeded }
        let model = try Self.xml(modelXML, root: "canvas")
        guard let root = model.rootElement() else { throw DocumentError.invalidXML }
        return try AnimationMetadata.read(root, maximumCount: maximumCount)
    }

    /// Copy an asset by its unique archive name, preserving arbitrary binary content.
    public func asset(named name: String) -> Data? {
        guard let item = items.first(where: { $0.name == name }) else { return nil }
        return Data(bytes[(payloadOffset + item.range.lowerBound)..<(payloadOffset + item.range.upperBound)])
    }

    /// Recognize Core's embedded-model archive namespace without reading any asset payload.
    package var hasEmbeddedModelAssets: Bool {
        items.contains { $0.type == "asset" && $0.name.hasPrefix("models/") }
    }

    /// Inventory retained image metadata in source order, including unused and unsupported resources.
    /// - Returns: Byte-stable grouped rows; pixel decoding remains a platform responsibility.
    /// This copies metadata only and never changes archive bytes.
    /// - Example: `document.colorImageAssets().filter(\.canAssign)` finds metadata-eligible images.
    public func colorImageAssets() -> [DocumentColorImageAsset] {
        DocumentTextureImages.inventory(assets: textureAssetMetadata())
    }

    /// Resolve distinct component color-image references to retained archive assets.
    /// - Returns: Source-ordered, alias-deduplicated metadata without copying/decoding image payloads.
    /// - Throws: `TextureImageReferenceError` for invalid, missing, ambiguous or wrong-kind
    ///   references; existing document errors for unsupported XML/component hierarchy.
    /// No bytes are changed. Callers can enforce encoded/decoded limits before asset(named:).
    /// - Example: `let references = try document.textureImageReferences()`.
    public func textureImageReferences() throws -> [DocumentTextureImageReference] {
        let model = try Self.xml(modelXML, root: "canvas")
        _ = try ComponentHierarchy.read(model)
        let imageIDs = PartSplitting.componentElements(model).compactMap {
            $0.attribute(forName: "colorImageId")?.stringValue
        }
        return try DocumentTextureImages.references(imageIDs: imageIDs, assets: textureAssetMetadata())
    }

    /// Qt-compatible reference image bytes, if canvas.png is an asset. Opaque input bytes are not decoded here.
    public var referenceImagePNG: Data? {
        guard hasReferenceImage else { return nil }
        return asset(named: "canvas.png")
    }

    /// Inspect the reference-image slot without copying its potentially large payload.
    public var hasReferenceImage: Bool { referenceImageByteCount != nil }

    /// Encoded reference-image length, without materializing its bytes; nil for an absent/non-asset slot.
    public var referenceImageByteCount: Int? {
        items.first { $0.name == "canvas.png" && $0.type == "asset" }?.range.count
    }

    /// Read the exact stored hollow thickness, including values from older archives.
    public func partHollowThicknessSource(id: String) throws -> String? {
        let model = try Self.xml(modelXML, root: "canvas")
        return try Self.hollowPart(in: model.rootElement(), id: id).attribute(forName: "hollowThickness")?.stringValue
    }

    private static func hollowPart(in root: XMLElement?, id: String) throws -> XMLElement {
        guard
            let part = root?.elements(forName: "parts").first?.elements(forName: "part").first(where: {
                $0.attribute(forName: "id")?.stringValue?.utf8.elementsEqual(id.utf8) == true
            })
        else { throw DocumentError.missingPart(id) }
        return part
    }

    /// Read a complete finite bounded canvas origin, or nil for missing/unsupported coordinates.
    /// Unsupported source attributes remain intact until an explicit origin edit or Undo.
    public func origin() throws -> NodePosition? {
        let model = try Self.xml(modelXML, root: "canvas")
        return model.rootElement().flatMap(Self.decodeOrigin)
    }

    private static func decodeOrigin(_ root: XMLElement) -> NodePosition? {
        let numbers = ["originX", "originY", "originZ"].compactMap {
            root.attribute(forName: $0)?.stringValue.flatMap(Double.init)
        }
        guard numbers.count == 3, numbers.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { return nil }
        return NodePosition(x: numbers[0], y: numbers[1], z: numbers[2])
    }

    /// Read components in XML preorder without changing the archive.
    /// - Returns: Ordered identities, parent/child links, names and uninterpreted source link attributes.
    /// - Throws: `invalidComponent` for ambiguous identities/containers or unsupported component tags; `limitExceeded` above 10,000 components.
    /// - Example: `try document.components().filter { $0.parentID == nil }` lists root components.
    public func components() throws -> [DocumentComponent] {
        try ComponentHierarchy.read(Self.xml(modelXML, root: "canvas"))
    }

    /// Read supported numeric fields of a node, or throw for a missing/invalid node.
    public func node(id: String) throws -> EditableNode {
        let xml = try Self.xml(modelXML, root: "canvas")
        let node = try Self.findNode(id, in: xml)
        return try Self.decodeNode(node)
    }

    private static func decodeNode(_ node: XMLElement) throws -> EditableNode {
        func number(_ name: String) throws -> Double {
            guard let value = node.attribute(forName: name)?.stringValue.flatMap(Double.init),
                value.isFinite, abs(value) <= 1_000_000
            else { throw DocumentError.invalidNode }
            return value
        }
        let radius = try number("radius")
        guard radius >= 0 else { throw DocumentError.invalidNode }
        return try EditableNode(position: NodePosition(x: number("x"), y: number("y"), z: number("z")), radius: radius)
    }

    /// Apply one validated command to a new document value, preserving all unrelated archive data.
    public func applying(_ command: DocumentCommand) throws -> Dust3DDocument {
        try applying(command, pasteParentID: nil)
    }

    /// Discover bounded identity requirements for splitting only the requested parts.
    public func partSplitRequirements(for partIDs: Set<String>) throws -> [PartSplitRequirement] {
        try PartSplitting.requirements(
            model: Self.xml(modelXML, root: "canvas"), contents: editorContents(), partIDs: partIDs)
    }

    package func applying(_ command: DocumentCommand, pasteParentID: String?) throws -> Dust3DDocument {
        if case .setComponentColors(let updates) = command {
            guard updates.count <= DocumentComponentColorUpdate.maximumBatchCount else {
                throw DocumentError.limitExceeded
            }
            if updates.isEmpty { return self }
            try Task.checkCancellation()
        }
        if case .setPartsState(let ids, _, _) = command {
            guard ids.count <= ComponentHierarchy.maximumCount else { throw DocumentError.limitExceeded }
            if ids.isEmpty { return self }
            try Task.checkCancellation()
        }
        let model = try Self.xml(modelXML, root: "canvas")
        let contents: DocumentContents
        var nextGraphOrder = graphOrder
        switch command {
        case .createAnimation, .setAnimationName, .setAnimationType, .setAnimationParameter, .duplicateAnimation,
            .deleteAnimation, .setRigType, .setHeadHasEyelids, .setNode, .setNodes, .setReferenceImagePNG, .setOrigin,
            .setComponentName, .setComponentColorImages, .importComponentColorImages,
            .setComponentCombineMode, .editComponentMeshSettings,
            .setComponentSmoothCutoffDegrees, .setComponentWrapMode, .editComponentWrapping, .setComponentWrapBinding,
            .setComponentWrapScalar,
            .setComponentWrapKeepChildren, .setComponentWrapFaces,
            .setComponentSurfacePattern, .setComponentSurfaceScalar, .setComponentSurfaceColor,
            .reorderComponent, .placeComponents,
            .groupComponents, .ungroupComponent, .ungroupComponents, .reparentComponent, .reparentComponents:
            contents = DocumentContents(nodes: [], edges: [])
        default: contents = try editorContents(in: model)
        }
        guard let root = model.rootElement() else { throw DocumentError.invalidXML }
        func container(_ name: String) -> XMLElement {
            if let existing = root.elements(forName: name).first { return existing }
            let created = XMLElement(name: name)
            root.addChild(created)
            return created
        }
        func element(_ name: String, _ attributes: [(String, String)]) -> XMLElement {
            let result = XMLElement(name: name)
            for (key, value) in attributes {
                let attribute = XMLNode(kind: .attribute)
                attribute.name = key
                attribute.stringValue = value
                result.addAttribute(attribute)
            }
            return result
        }
        func setPartFlag(
            _ part: XMLElement, current: DocumentPart, property: PartStateProperty, value: Bool
        ) -> Bool {
            guard current.state(property) != value else { return false }
            part.removeAttribute(forName: property.rawValue)
            let attribute = XMLNode(kind: .attribute)
            attribute.name = property.rawValue
            attribute.stringValue = value ? "true" : "false"
            part.addAttribute(attribute)
            return true
        }
        func editable(_ id: String) throws -> DocumentNode {
            guard let node = contents.nodes.first(where: { $0.id == id }), node.isEditable else {
                throw DocumentError.invalidNode
            }
            return node
        }
        func edgeElements() -> [XMLElement] { root.elements(forName: "edges").first?.elements(forName: "edge") ?? [] }
        switch command {
        case .createAnimation(let id, let name, let type):
            try AnimationMetadata.create(root, id: id, name: name, type: type)
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setAnimationName(let id, let name):
            guard try AnimationMetadata.setField(root, id: id, field: .name, value: name) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setAnimationType(let id, let type):
            guard try AnimationMetadata.setField(root, id: id, field: .type, value: type) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setAnimationParameter(let id, let name, let value):
            guard try AnimationMetadata.setParameter(root, id: id, name: name, value: value) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .duplicateAnimation(let id, let newID, let name):
            try AnimationMetadata.duplicate(root, id: id, newID: newID, name: name)
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .deleteAnimation(let id):
            try AnimationMetadata.delete(root, id: id)
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setEdgeBoneName(let id, let name):
            guard try EdgeBoneBinding.set(model: model, contents: contents, id: id, name: name) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setEdgeBoneNames(let ids, let name):
            guard try EdgeBoneBinding.setMany(model: model, contents: contents, ids: ids, name: name) else {
                return self
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .clearEdgeBoneNames(let ids):
            guard try EdgeBoneBinding.clearMany(model: model, contents: contents, ids: ids) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setRigType(let type):
            if DocumentRigSettings(root: root).rigType == type { return self }
            DocumentRigMetadata.set(root: root, name: "rigType", value: type.rawValue)
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setHeadHasEyelids(let enabled):
            if DocumentRigSettings(root: root).headHasEyelids == enabled { return self }
            DocumentRigMetadata.set(root: root, name: "headHasEyelids", value: enabled ? "true" : nil)
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setReferenceImagePNG(let png): return try replacingReferenceImage(png)
        case .setOrigin(let position):
            guard [position.x, position.y, position.z].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else {
                throw DocumentError.invalidOrigin
            }
            if Self.decodeOrigin(root) == position { return self }
            for (name, value) in [("originX", position.x), ("originY", position.y), ("originZ", position.z)] {
                let text = String(value == 0 ? 0 : value)
                if let attribute = root.attribute(forName: name) {
                    attribute.stringValue = text
                } else {
                    let attribute = XMLNode(kind: .attribute)
                    attribute.name = name
                    attribute.stringValue = text
                    root.addAttribute(attribute)
                }
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .groupComponents(let ids, let groupID):
            try ComponentStructure.group(model, ids: ids, groupID: groupID)
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .ungroupComponents(let ids):
            guard try ComponentUngroupBatch.apply(model, ids: ids) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .ungroupComponent(let id):
            guard try ComponentStructure.ungroup(model, id: id) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .reparentComponents(let ids, let parentID):
            guard try ComponentReparentBatch.apply(model, ids: ids, parentID: parentID) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .reparentComponent(let id, let parentID):
            guard try ComponentStructure.reparent(model, id: id, parentID: parentID) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .placeComponents(let ids, let placement):
            if case .into(let parentID) = placement {
                guard try ComponentReparentBatch.apply(model, ids: ids, parentID: parentID, appendBlock: true) else {
                    return self
                }
            } else {
                guard try ComponentReordering.apply(model, ids: ids, placement: placement) else { return self }
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .reorderComponent(let id, let direction):
            guard try ComponentReordering.apply(model, id: id, direction: direction) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .editComponentMeshSettings(let ids, let edit):
            guard try ComponentMeshBatch.apply(model, ids: ids, edit: edit) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentSmoothCutoffDegrees(let id, let degrees):
            guard try ComponentSmoothing.set(model, id: id, degrees: degrees) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentCombineMode(let id, let mode):
            guard try ComponentCombination.set(model, id: id, mode: mode) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentColors(let updates):
            guard try ComponentColorValue.set(model, updates: updates) else { return self }
            try Task.checkCancellation()
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentColorImages(let ids, let imageID):
            let elements = try ComponentColorImageValue.elements(model, ids: ids)
            guard !elements.isEmpty else { return self }
            let canonical = try imageID.map {
                try DocumentTextureImages.reference(imageID: $0, assets: textureAssetMetadata()).imageID
            }
            guard try ComponentColorImageValue.set(elements, imageID: canonical) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .importComponentColorImages(let ids, let imageID, let png):
            let elements = try ComponentColorImageValue.elements(model, ids: ids)
            guard !elements.isEmpty else { return self }
            _ = try PNGContainerMetadata(data: png)
            guard let identity = DocumentTextureImages.identityBytes(imageID) else {
                throw TextureImageReferenceError.invalidImageIdentity(imageID)
            }
            let canonical = "{" + String(decoding: identity, as: UTF8.self) + "}"
            let changed = try ComponentColorImageValue.set(elements, imageID: canonical)
            return try importingColorImage(
                imageID: imageID, png: png, replacementModel: changed ? model.xmlData(options: [.nodePreserveAll]) : nil
            )
        case .setComponentColorImage(let id, let imageID):
            let element = try ComponentColorImageValue.element(model, id: id)
            let canonical: String?
            if let imageID {
                canonical = try DocumentTextureImages.reference(imageID: imageID, assets: textureAssetMetadata())
                    .imageID
            } else {
                canonical = nil
            }
            guard ComponentColorImageValue.set(element, imageID: canonical) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .importComponentColorImage(let id, let imageID, let png):
            _ = try ComponentColorImageValue.element(model, id: id)
            _ = try PNGContainerMetadata(data: png)
            return try importingColorImage(imageID: imageID, png: png).applying(
                .setComponentColorImage(id: id, imageID: imageID))
        case .setComponentColor(let id, let color):
            guard try ComponentColorValue.set(model, id: id, color: color) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentEquipmentSlot(let id, let slot):
            guard try ComponentHierarchy.setEquipmentSlot(model, parts: contents.parts, id: id, slot: slot) else {
                return self
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentName(let id, let name):
            guard try ComponentHierarchy.rename(model, id: id, name: name) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartHollowThickness(let id, let thickness):
            guard thickness.isFinite, (0...1).contains(thickness) else {
                throw DocumentError.invalidPartHollowThickness
            }
            let part = try Self.hollowPart(in: root, id: id)
            let key = "hollowThickness"
            let current = part.attribute(forName: key)
            if (current?.stringValue.flatMap(Double.init) ?? (current == nil ? 0 : nil)) == thickness { return self }
            part.removeAttribute(forName: key)
            if thickness > 0 {
                let attribute = XMLNode(kind: .attribute)
                attribute.name = key
                attribute.stringValue = String(thickness)
                part.addAttribute(attribute)
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartName(let id, let name):
            guard name.utf8.count <= 1024,
                name.unicodeScalars.allSatisfy({
                    $0.value >= 0x20 && $0.value != 0xFFFE && $0.value != 0xFFFF
                        && !CharacterSet.newlines.contains($0)
                })
            else { throw DocumentError.invalidPartName }
            guard let current = contents.parts.first(where: { $0.id == id }),
                let part = root.elements(forName: "parts").first?.elements(forName: "part").first(where: {
                    $0.attribute(forName: "id")?.stringValue == id
                })
            else { throw DocumentError.missingPart(id) }
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.name == value { return self }
            part.removeAttribute(forName: "name")
            if !value.isEmpty {
                let attribute = XMLNode(kind: .attribute)
                attribute.name = "name"
                attribute.stringValue = value
                part.addAttribute(attribute)
            }
        case .setComponentSurfacePattern(let id, let pattern):
            guard try ComponentSurfaceMetadata.pattern(model, id: id, pattern: pattern) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentSurfaceScalar(let id, let property, let value):
            guard try ComponentSurfaceMetadata.scalar(model, id: id, property: property, value: value) else {
                return self
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentSurfaceColor(let id, let color):
            guard try ComponentSurfaceMetadata.color(model, id: id, color: color) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .editComponentWrapping(let ids, let edit):
            guard try ComponentWrappingBatch.apply(model, ids: ids, edit: edit) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentWrapBinding(let id, let choice):
            guard try ComponentWrapBindingXML.set(model, id: id, choice: choice) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentWrapMode(let id, let mode):
            guard try ComponentWrapping.setMode(model, id: id, mode: mode) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentWrapScalar(let id, let property, let value):
            guard try ComponentWrapping.setScalar(model, id: id, property: property, value: value) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentWrapKeepChildren(let id, let value):
            guard try ComponentWrapping.setKeep(model, id: id, value: value) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentWrapFaces(let id, let faces):
            guard try ComponentWrapping.setFaces(model, id: id, faces: faces) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentStitchingClosure(let id, let property, let value):
            guard try ComponentStitching.setClosure(model, id: id, property: property, value: value) else {
                return self
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentStitchingScalar(let id, let property, let value):
            guard try ComponentStitching.setScalar(model, id: id, property: property, value: value) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentTargetSegments(let id, let segments):
            guard try ComponentStitching.setSegments(model, id: id, segments: segments) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartFillLoopInterior(let id, let value):
            guard try PartLoopInterior.set(model, parts: contents.parts, id: id, value: value) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentPartRoles(let componentIDs, let target, let groupID):
            guard
                try ComponentStructure.setPartRoles(
                    model, parts: contents.parts, ids: componentIDs, target: target, groupID: groupID)
            else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartTarget(let id, let target):
            guard try PartTargetMetadata.set(model, parts: contents.parts, id: id, target: target) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartCutFace(let id, let selection):
            guard try PartCutFace.setSelection(model, parts: contents.parts, id: id, selection: selection) else {
                return self
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartCutRotation(let id, let rotation):
            guard try PartCutFace.setRotation(model, parts: contents.parts, id: id, rotation: rotation) else {
                return self
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartMaterial(let id, let property, let value):
            guard try PartMaterial.set(model, parts: contents.parts, id: id, property: property, value: value)
            else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartDeformationScale(let id, let property, let value):
            guard try PartDeformation.setScale(model, parts: contents.parts, id: id, property: property, value: value)
            else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartDeformationUnified(let id, let value):
            guard try PartDeformation.setUnified(model, parts: contents.parts, id: id, value: value) else {
                return self
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartXMirrored(let id, let value):
            guard try PartMirrorMetadata.set(root, contents: contents, id: id, value: value) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartModifier(let id, let property, let value):
            guard try PartModifiers.set(model, parts: contents.parts, id: id, property: property, value: value) else {
                return self
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartState(let id, let property, let value):
            guard let current = contents.parts.first(where: { $0.id == id }),
                let part = root.elements(forName: "parts").first?.elements(forName: "part").first(where: {
                    $0.attribute(forName: "id")?.stringValue == id
                })
            else { throw DocumentError.missingPart(id) }
            guard setPartFlag(part, current: current, property: property, value: value) else { return self }
        case .setPartsState(let ids, let property, let value):
            let current = Dictionary(
                contents.parts.map { (Data($0.id.utf8), $0) }, uniquingKeysWith: { first, _ in first })
            let elements = Dictionary(
                (root.elements(forName: "parts").first?.elements(forName: "part") ?? []).compactMap { part in
                    part.attribute(forName: "id")?.stringValue.map { (Data($0.utf8), part) }
                }, uniquingKeysWith: { first, _ in first })
            var changed = false
            var seen = Set<Data>()
            for id in ids where seen.insert(Data(id.utf8)).inserted {
                try Task.checkCancellation()
                guard let part = elements[Data(id.utf8)], let metadata = current[Data(id.utf8)] else {
                    throw DocumentError.missingPart(id)
                }
                if setPartFlag(part, current: metadata, property: property, value: value) { changed = true }
            }
            guard changed else { return self }
        case .addNode(let id, let partID, let componentID, let position, let radius):
            guard !id.isEmpty, !partID.isEmpty, !contents.nodes.contains(where: { $0.id == id }),
                contents.nodes.count < 10_000,
                EditableNode(position: position, radius: radius).isValid
            else { throw DocumentError.invalidNode }
            let parts = container("parts")
            if let part = parts.elements(forName: "part").first(where: {
                $0.attribute(forName: "id")?.stringValue == partID
            }) {
                func isTrue(_ value: String?) -> Bool { value == "true" || value == "True" || value == "1" }
                guard !isTrue(part.attribute(forName: "locked")?.stringValue),
                    !isTrue(part.attribute(forName: "disabled")?.stringValue),
                    part.attribute(forName: "visible").map({ isTrue($0.stringValue) }) ?? true
                else { throw DocumentError.invalidNode }
            } else {
                let components = PartSplitting.componentElements(model)
                guard components.count < 10_000 else { throw DocumentError.limitExceeded }
                guard let componentID, !componentID.isEmpty,
                    !components.contains(where: {
                        $0.attribute(forName: "id")?.stringValue == componentID
                    })
                else { throw DocumentError.invalidNode }
                parts.addChild(
                    element("part", [("id", partID), ("name", "Part"), ("visible", "true"), ("locked", "false")]))
                container("components").addChild(
                    element(
                        "component",
                        [
                            ("id", componentID), ("name", "Part"), ("linkData", partID), ("linkDataType", "partId"),
                            ("combineMode", "Normal"),
                        ]))
            }
            container("nodes").addChild(
                element(
                    "node",
                    [
                        ("id", id), ("partId", partID), ("x", String(position.x)), ("y", String(position.y)),
                        ("z", String(position.z)), ("radius", String(radius)),
                    ]))
        case .addEdge(let id, let from, let to):
            let source = try editable(from)
            let target = try editable(to)
            guard !id.isEmpty, from != to, let partID = source.partID, target.partID == partID,
                contents.edges.count < 20_000,
                !contents.edges.contains(where: {
                    $0.id == id || ($0.fromID == from && $0.toID == to) || ($0.fromID == to && $0.toID == from)
                })
            else { throw DocumentError.invalidNode }
            container("edges").addChild(element("edge", [("id", id), ("partId", partID), ("from", from), ("to", to)]))
        case .insertEdgeMidpoint(let id, let nodeID, let edgeID):
            try EdgeMidpoints.apply(
                [.init(originalEdgeID: id, nodeID: nodeID, edgeID: edgeID)],
                model: model, contents: contents, order: &nextGraphOrder)
        case .insertEdgeMidpoints(let requests):
            guard !requests.isEmpty else { return self }
            try EdgeMidpoints.apply(requests, model: model, contents: contents, order: &nextGraphOrder)
        case .joinNodes(let id, let from, let to):
            try PartJoining.apply(id: id, from: from, to: to, model: model, contents: contents)
        case .reduceNodes(let ids):
            guard try NodeReduction.apply(ids, model: model, contents: contents, order: &nextGraphOrder) else {
                return self
            }
        case .removeComponentSubtrees(let ids):
            guard try ComponentSubtreeDeletion.apply(model, contents: contents, ids: ids) else { return self }
        case .removeNode(let id):
            return try applying(.removeNodes([id]))
        case .removeNodes(let ids):
            if ids.isEmpty { return self }
            let removed = Set(ids)
            let nodes = Dictionary(uniqueKeysWithValues: contents.nodes.map { ($0.id, $0) })
            guard removed.count == ids.count, ids.allSatisfy({ nodes[$0]?.isEditable == true }) else {
                throw DocumentError.invalidNode
            }
            for node in try Self.nodes(model) where removed.contains(node.attribute(forName: "id")?.stringValue ?? "") {
                node.detach()
            }
            for edge in edgeElements()
            where removed.contains(edge.attribute(forName: "from")?.stringValue ?? "")
                || removed.contains(edge.attribute(forName: "to")?.stringValue ?? "")
            {
                edge.detach()
            }
        case .pruneEmptyParts(let ids):
            if ids.isEmpty { return self }
            try EmptyPartCleanup.apply(ids, model: model, contents: contents)
        case .removeEdge(let id):
            _ = try EdgeRemoval.apply([id], model: model, contents: contents)
        case .removeEdges(let ids):
            guard try EdgeRemoval.apply(ids, model: model, contents: contents) else { return self }
        case .reverseEdges(let ids):
            if ids.isEmpty { return self }
            let edges = Dictionary(uniqueKeysWithValues: contents.edges.map { ($0.id, $0) })
            let editable = Set(contents.nodes.filter(\.isEditable).map(\.id))
            guard Set(ids).count == ids.count,
                ids.allSatisfy({ id in
                    guard let edge = edges[id] else { return false }
                    return editable.contains(edge.fromID) && editable.contains(edge.toID)
                })
            else { throw DocumentError.invalidNode }
            let selected = Set(ids)
            for edge in edgeElements() where selected.contains(edge.attribute(forName: "id")?.stringValue ?? "") {
                let from = edge.attribute(forName: "from")?.stringValue
                let to = edge.attribute(forName: "to")?.stringValue
                edge.attribute(forName: "from")?.stringValue = to
                edge.attribute(forName: "to")?.stringValue = from
            }
        case .pasteNodes(let clipboard, let identities, let offset, let partitions):
            var namespaceBudget = DocumentXML.NamespaceBudget()
            try NodeClipboardMutation.paste(
                clipboard, identities: identities, offset: offset, into: model, contents: contents,
                namespaceBudget: &namespaceBudget, parentID: pasteParentID)
            let pastedEdges = try clipboard.document.editorContents().edges.sorted {
                $0.id.utf8.lexicographicallyPrecedes($1.id.utf8)
            }
            for edge in pastedEdges {
                guard let edgeID = identities[edge.id], let from = identities[edge.fromID],
                    let to = identities[edge.toID]
                else {
                    throw DocumentError.invalidNode
                }
                nextGraphOrder.incident[from, default: []].append(edgeID)
                nextGraphOrder.incident[to, default: []].append(edgeID)
            }
            var result = try replacingModel(model.xmlData(options: [.nodePreserveAll])).mergingAssets(
                from: clipboard.document, namespaceBudget: &namespaceBudget)
            result.graphOrder = nextGraphOrder.reconciled(with: model)
            let contents = try result.editorContents()
            let pastedParts = Set(
                try clipboard.document.editorContents().nodes.compactMap(\.partID).compactMap { identities[$0] })
            guard Set(partitions.keys).isSubset(of: pastedParts) else { throw DocumentError.invalidNode }
            let identityCount = partitions.values.reduce(0) { total, plans in
                total + plans.reduce(0) { $0 + 1 + $1.componentIDs.count }
            }
            guard identityCount <= 20_000 else { throw DocumentError.limitExceeded }
            let fresh = partitions.values.flatMap { $0 }.flatMap { [$0.partID] + $0.componentIDs }
            let keys = fresh.map { CutFaceLinks.canonicalID($0) ?? $0 }
            let existing = Set(
                NodeClipboardMutation.semanticElements(model).compactMap { $0.attribute(forName: "id")?.stringValue }
                    .map { CutFaceLinks.canonicalID($0) ?? $0 })
            guard Set(keys).count == keys.count, existing.isDisjoint(with: keys) else {
                throw DocumentError.invalidNode
            }
            for id in partitions.keys.sorted() {
                _ = try PartSplitting.apply(
                    id: id, identities: partitions[id] ?? [], model: model, contents: contents, allowReadOnly: true)
            }
            if !partitions.isEmpty { result = try result.replacingModel(model.xmlData(options: [.nodePreserveAll])) }
            _ = try result.editorContents()
            return result
        case .splitPart(let id, let identities):
            if try !PartSplitting.apply(id: id, identities: identities, model: model, contents: contents) {
                return self
            }
        case .setNodeDeformationScale(let id, let property, let value):
            guard NodeDeformation.isValid(value) else { throw DocumentError.invalidNodeDeformation }
            guard let node = contents.nodes.first(where: { $0.id.utf8.elementsEqual(id.utf8) }) else {
                throw DocumentError.missingNode(id)
            }
            guard node.isEditable, let partID = node.partID,
                contents.parts.first(where: { $0.id.utf8.elementsEqual(partID.utf8) })?.target == .model
            else { throw DocumentError.invalidNode }
            guard node.deformationScale(property) != value else { return self }
            guard
                let element = try Self.nodes(model).first(where: {
                    $0.attribute(forName: "id")?.stringValue?.utf8.elementsEqual(id.utf8) == true
                })
            else { throw DocumentError.missingNode(id) }
            NodeDeformation.write(property, value: value, on: element)
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setNode(let id, let position, let radius):
            return try applying(.setNodes([.init(id: id, value: .init(position: position, radius: radius))]))
        case .setNodes(let updates):
            guard Set(updates.map(\.id)).count == updates.count else { throw DocumentError.invalidNode }
            let elements = Dictionary(
                uniqueKeysWithValues: try Self.nodes(model).map {
                    ($0.attribute(forName: "id")?.stringValue ?? "", $0)
                })
            var changed = false
            for update in updates {
                guard update.value.isValid else { throw DocumentError.invalidNode }
                guard let node = elements[update.id] else { throw DocumentError.missingNode(update.id) }
                if try Self.decodeNode(node) == update.value { continue }
                changed = true
                let position = update.value.position
                for (key, value) in [
                    ("x", position.x), ("y", position.y), ("z", position.z), ("radius", update.value.radius),
                ] {
                    node.attribute(forName: key)?.stringValue = String(value)
                }
            }
            if !changed { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        }
        var next = try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        next.graphOrder = nextGraphOrder.reconciled(with: model)
        _ = try next.editorContents()
        return next
    }

    /// Compare persisted bytes and process-local graph ordering that affects future editing commands.
    /// - Parameter other: Another immutable document snapshot.
    /// - Returns: True only when both archive content and future incident-edge behavior are identical.
    /// - Example: `document.hasSameEditingState(as: history.document)`.
    public func hasSameEditingState(as other: Dust3DDocument) -> Bool {
        encoded() == other.encoded() && hasSameGraphOrder(as: other)
    }

    var historyByteCost: Int { encoded().count + graphOrder.historyByteCost }

    func preservingGraphOrder(from other: Dust3DDocument) -> Self {
        var result = self
        result.graphOrder = other.graphOrder
        return result
    }

    func hasSameGraphOrder(as other: Dust3DDocument) -> Bool { graphOrder == other.graphOrder }

    // Normalize known serialization differences for net-zero transactions, while comparing every asset and header field.
    func hasSameContents(as other: Dust3DDocument) throws -> Bool {
        func canonicalHeader(_ data: Data) throws -> Data {
            let header = try Self.xml(data, root: "ds3")
            header.isStandalone = false
            for child in header.rootElement()?.children ?? [] {
                guard let element = child as? XMLElement else { continue }
                element.removeAttribute(forName: "offset")
                element.removeAttribute(forName: "size")
            }
            return header.xmlData(options: [.nodePreserveAll])
        }
        guard items.count == other.items.count,
            try canonicalHeader(header) == canonicalHeader(other.header)
        else { return false }
        for (index, item) in items.enumerated() where index != modelIndex {
            let counterpart = other.items[index]
            guard
                bytes[(payloadOffset + item.range.lowerBound)..<(payloadOffset + item.range.upperBound)]
                    == other.bytes[
                        (other.payloadOffset + counterpart.range.lowerBound)..<(other.payloadOffset
                            + counterpart.range.upperBound)]
            else { return false }
        }
        return try hasSameModel(as: other)
    }

    /// Model-only transactions cannot alter assets; avoid traversing opaque payloads on interactive graph edits.
    func hasSameModel(as other: Dust3DDocument) throws -> Bool {
        func canonical(_ data: Data) throws -> Data {
            let model = try Self.xml(data, root: "canvas", preserveSourceSpelling: false)
            model.isStandalone = false
            // Attribute order is not animation intent. Reorder only the parsed comparison tree;
            // a net-zero transaction restores the original archive rather than serializing this order.
            for container in DocumentXML.childElements(model.rootElement(), named: "animations") {
                for animation in DocumentXML.childElements(container, named: "animation") {
                    let attributes = (animation.attributes ?? []).sorted {
                        ($0.name ?? "").utf8.lexicographicallyPrecedes(($1.name ?? "").utf8)
                    }
                    for attribute in attributes { attribute.detach() }
                    for attribute in attributes { animation.addAttribute(attribute) }
                }
            }
            // Absent graph/animation containers and metadata-free empty ones have the same stored intent.
            // Attributes, namespaces, comments and non-whitespace content are metadata.
            for name in ["nodes", "edges", "animations"] {
                for container in model.rootElement()?.elements(forName: name) ?? [] {
                    if container.attributes?.isEmpty ?? true, container.namespaces?.isEmpty ?? true,
                        (container.children ?? []).allSatisfy({
                            $0.kind == .text
                                && $0.xmlString(options: [.nodePreserveAll]).trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                        })
                    {
                        container.detach()
                    }
                }
            }
            for key in ["originX", "originY", "originZ"] {
                if let attribute = model.rootElement()?.attribute(forName: key),
                    let number = attribute.stringValue.flatMap(Double.init), number.isFinite, abs(number) <= 1_000_000
                {
                    attribute.stringValue = String(number == 0 ? 0 : number)
                }
            }
            for node in try Self.nodes(model) {
                for key in ["x", "y", "z", "radius"] {
                    if let attribute = node.attribute(forName: key),
                        let number = attribute.stringValue.flatMap(Double.init), number.isFinite
                    {
                        attribute.stringValue = String(number == 0 ? 0 : number)
                    }
                }
            }
            for part in model.rootElement()?.elements(forName: "parts").first?.elements(forName: "part") ?? [] {
                for property in PartStateProperty.allCases {
                    guard let attribute = part.attribute(forName: property.rawValue) else { continue }
                    let value = ["true", "True", "1"].contains(attribute.stringValue ?? "")
                    let defaultValue = property == .visible
                    if value == defaultValue {
                        part.removeAttribute(forName: property.rawValue)
                    } else {
                        attribute.stringValue = value ? "true" : "false"
                    }
                }
            }
            for component in PartSplitting.componentElements(model) {
                guard let attribute = component.attribute(forName: "colorImageId"), let text = attribute.stringValue
                else { continue }
                if text.isEmpty {
                    component.removeAttribute(forName: "colorImageId")
                } else if let identity = DocumentTextureImages.identityBytes(text) {
                    attribute.stringValue = "{" + String(decoding: identity, as: UTF8.self) + "}"
                }
            }
            return model.xmlData()
        }
        return try canonical(modelXML) == canonical(other.modelXML)
    }

    package func replayProperties() throws -> [ReplayProperty] {
        let model = try Self.xml(modelXML, root: "canvas")
        let parts = model.rootElement()?.elements(forName: "parts").first?.elements(forName: "part") ?? []
        let partRules = [
            ("target", "Part Target"),
            ("xMirrored", "X Mirror"), ("rounded", "Rounded Ends"), ("chamfered", "Chamfer"),
            ("subdived", "Subdivision"), ("interpolated", "Interpolation"), ("hard", "Hard Join"),
            ("fillLoopInterior", "Fill Loop Interior"), ("deformThickness", "Thickness"),
            ("deformWidth", "Width"), ("deformUnified", "Unified Deformation"), ("cutFace", "Cut Face"),
            ("cutRotation", "Cut Rotation"), ("hollowThickness", "Hollow Thickness"),
            ("metallic", "Metallic"), ("roughness", "Roughness"), ("disabled", "Part Enabled State"),
        ]
        let componentRules = [
            ("combineMode", "Combine Mode"), ("color", "Color"), ("colorImageId", "Color Image"),
            ("sideClosed", "Close Sides"), ("frontClosed", "Close Front"), ("backClosed", "Close Back"),
            ("backCloseDepthRatio", "Back Closure Depth"), ("backCloseSharpness", "Back Closure Sharpness"),
            ("targetSegments", "Target Segments"), ("smoothCutoffDegrees", "Smoothing Cutoff"),
        ]
        func properties(
            _ elements: [XMLElement], owner: ReplayProperty.Owner, rules: [(String, String)]
        ) -> [ReplayProperty] {
            elements.flatMap { element -> [ReplayProperty] in
                guard let id = element.attribute(forName: "id")?.stringValue else { return [] }
                let name = element.attribute(forName: "name")?.stringValue ?? ""
                var result = rules.compactMap { attribute, label -> ReplayProperty? in
                    guard let value = element.attribute(forName: attribute)?.stringValue else { return nil }
                    if attribute == "target", value != "ImportedModel" {
                        guard let target = PartTarget(rawValue: value), target != .model else { return nil }
                    }
                    let profilePartID =
                        attribute == "cutFace" && CutFaceLinks.canonicalID(value) != nil
                        ? value : nil
                    return ReplayProperty(
                        owner: owner, id: id, attributes: [attribute],
                        title: name.isEmpty ? label : "\(name) — \(label)", profilePartID: profilePartID)
                }
                if owner == .component,
                    (element.attribute(forName: "linkDataType")?.stringValue ?? "").isEmpty,
                    (element.attribute(forName: "linkData")?.stringValue ?? "").isEmpty,
                    let value = element.attribute(forName: "wrap")?.stringValue, !value.isEmpty
                {
                    let attributes = (element.attributes ?? []).compactMap(\.name).filter { $0.hasPrefix("wrap") }
                    result.append(
                        ReplayProperty(
                            owner: owner, id: id, attributes: attributes,
                            title: name.isEmpty ? "Wrap Modifier" : "\(name) — Wrap Modifier", profilePartID: nil))
                }
                return result
            }
        }
        return properties(
            try Self.nodes(model), owner: .node,
            rules: [
                ("cutFace", "Node Cut Face"), ("cutRotation", "Node Cut Rotation"),
            ]) + properties(parts, owner: .part, rules: partRules)
            + properties(PartSplitting.componentElements(model), owner: .component, rules: componentRules)
    }

    /// Produce a transient archive for a replay frame, retaining source assets and metadata.
    package func replayFrame(
        nodeIDs: Set<String>, edgeIDs: Set<String>, pendingProperties: [ReplayProperty] = [],
        pendingGroupIDs: Set<String> = [], pendingMoveIDs: Set<String> = [],
        reversedEdgeIDs: Set<String> = [], hidesRigType: Bool = false,
        unassignedBoneEdgeIDs: Set<String> = [], pendingAnimationIDs: Set<[UInt8]> = []
    ) throws -> Dust3DDocument {
        let model = try Self.xml(modelXML, root: "canvas")
        guard let root = model.rootElement() else { throw DocumentError.invalidNode }
        if hidesRigType { root.removeAttribute(forName: "rigType") }
        var retainedParts = Set<String>()
        for node in try Self.nodes(model) {
            guard let id = node.attribute(forName: "id")?.stringValue, nodeIDs.contains(id) else {
                node.detach()
                continue
            }
            if let part = node.attribute(forName: "partId")?.stringValue { retainedParts.insert(part) }
        }
        for edge in root.elements(forName: "edges").first?.elements(forName: "edge") ?? [] {
            guard let id = edge.attribute(forName: "id")?.stringValue, edgeIDs.contains(id),
                let from = edge.attribute(forName: "from")?.stringValue, nodeIDs.contains(from),
                let to = edge.attribute(forName: "to")?.stringValue, nodeIDs.contains(to)
            else {
                edge.detach()
                continue
            }
            if unassignedBoneEdgeIDs.contains(id) { edge.removeAttribute(forName: "boneName") }
            if reversedEdgeIDs.contains(id) {
                edge.attribute(forName: "from")?.stringValue = to
                edge.attribute(forName: "to")?.stringValue = from
            }
        }
        for part in root.elements(forName: "parts").first?.elements(forName: "part") ?? []
        where !retainedParts.contains(part.attribute(forName: "id")?.stringValue ?? "") {
            part.detach()
        }
        for entry in root.elements(forName: "partIdList").first?.elements(forName: "partId") ?? []
        where !retainedParts.contains(entry.attribute(forName: "id")?.stringValue ?? "") {
            entry.detach()
        }
        func pruneComponents(in parent: XMLElement) {
            for component in parent.elements(forName: "component") {
                pruneComponents(in: component)
                guard component.attribute(forName: "linkDataType")?.stringValue == "partId",
                    !retainedParts.contains(component.attribute(forName: "linkData")?.stringValue ?? "")
                else { continue }
                if component.elements(forName: "component").isEmpty {
                    component.detach()
                } else {
                    component.removeAttribute(forName: "linkDataType")
                    component.removeAttribute(forName: "linkData")
                }
            }
        }
        if let components = root.elements(forName: "components").first {
            pruneComponents(in: components)
            if !pendingGroupIDs.isEmpty || !pendingMoveIDs.isEmpty {
                let elements = PartSplitting.componentElements(model)
                var namespaceBudget = DocumentXML.NamespaceBudget()
                // Parts are initially at the root and must survive removal of their future groups.
                for element in elements {
                    guard let id = element.attribute(forName: "id")?.stringValue,
                        pendingMoveIDs.contains(id)
                    else { continue }
                    try namespaceBudget.preserve(element, movingTo: components)
                    element.detach()
                    components.addChild(element)
                }
                for element in elements.reversed() {
                    guard let id = element.attribute(forName: "id")?.stringValue,
                        pendingGroupIDs.contains(id)
                    else { continue }
                    element.detach()
                }
            }
        }
        let pending = Dictionary(grouping: pendingProperties, by: \.owner)
        func mask(_ elements: [XMLElement], owner: ReplayProperty.Owner) {
            let attributes = Dictionary(grouping: pending[owner] ?? [], by: { Array($0.id.utf8) })
            for element in elements {
                guard let id = element.attribute(forName: "id")?.stringValue else { continue }
                for property in attributes[Array(id.utf8)] ?? [] {
                    for attribute in property.attributes { element.removeAttribute(forName: attribute) }
                }
            }
        }
        mask(try Self.nodes(model), owner: .node)
        mask(root.elements(forName: "parts").first?.elements(forName: "part") ?? [], owner: .part)
        mask(PartSplitting.componentElements(model), owner: .component)
        if !pendingAnimationIDs.isEmpty || pending[.animation] != nil {
            let animations = try AnimationMetadata.elements(root)
            for animation in animations {
                let id = animation.attribute(forName: "id")?.stringValue ?? ""
                if pendingAnimationIDs.contains(Array(id.utf8)) { animation.detach() }
            }
            mask(animations, owner: .animation)
        }
        return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
    }

    private func replacingModel(_ model: Data) throws -> Dust3DDocument {
        guard model.count <= 16 * 1024 * 1024 else { throw DocumentError.limitExceeded }
        return try replacingItem(at: modelIndex, with: model)
    }

    private func textureAssetMetadata() -> [DocumentTextureAssetMetadata] {
        items.map { DocumentTextureAssetMetadata(name: $0.name, kind: $0.type, byteCount: $0.range.count) }
    }

    private func importingColorImage(
        imageID: String, png: Data, replacementModel: Data? = nil
    ) throws -> Dust3DDocument {
        guard let identity = DocumentTextureImages.identityBytes(imageID),
            !identity.contains(47), !identity.contains(46),
            imageID.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0) && $0.value != 0xFFFE && $0.value != 0xFFFF
            })
        else { throw TextureImageReferenceError.invalidImageIdentity(imageID) }
        let canonical = "{" + String(decoding: identity, as: UTF8.self) + "}"
        let assetName = "images/\(canonical).png"
        do {
            let existing = try DocumentTextureImages.reference(imageID: canonical, assets: textureAssetMetadata())
            guard asset(named: existing.assetName) == png else {
                throw DocumentError.conflictingAsset(existing.assetName)
            }
            return try replacementModel.map { try replacingModel($0) } ?? self
        } catch TextureImageReferenceError.missingAsset {
            // A fresh import must not implicitly repair other components' missing resources.
            let model = try Self.xml(modelXML, root: "canvas")
            guard
                !PartSplitting.componentElements(model).contains(where: {
                    DocumentTextureImages.identityBytes($0.attribute(forName: "colorImageId")?.stringValue ?? "")
                        == identity
                })
            else { throw DocumentError.conflictingAsset(assetName) }
        }
        guard !items.contains(where: { $0.name == assetName }) else { throw DocumentError.conflictingAsset(assetName) }
        guard items.count < 10_000, bytes.count - payloadOffset <= 256 * 1024 * 1024 - png.count else {
            throw DocumentError.limitExceeded
        }
        let xml: XMLDocument
        var payload: Data
        if let replacementModel {
            guard replacementModel.count <= 16 * 1024 * 1024 else { throw DocumentError.limitExceeded }
            (xml, payload) = try replacingItemPayload(at: modelIndex, with: replacementModel)
        } else {
            xml = try Self.xml(header, root: "ds3")
            payload = Data(bytes[payloadOffset...])
        }
        guard payload.count <= 256 * 1024 * 1024 - png.count else { throw DocumentError.limitExceeded }
        let asset = XMLElement(name: "asset")
        for (name, value) in [
            ("name", assetName), ("offset", String(payload.count)), ("size", String(png.count)),
        ] {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = name
            attribute.stringValue = value
            asset.addAttribute(attribute)
        }
        xml.rootElement()?.addChild(asset)
        payload.append(png)
        return try rebuildingArchive(xml, payload: payload)
    }

    private func replacingReferenceImage(_ png: Data?) throws -> Dust3DDocument {
        if let png {
            guard png.count <= 32 * 1024 * 1024 else { throw DocumentError.limitExceeded }
            guard png.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else {
                throw DocumentError.invalidReferenceImage
            }
        }
        if let index = items.firstIndex(where: { $0.name == "canvas.png" }) {
            guard items[index].type == "asset" else { throw DocumentError.conflictingAsset("canvas.png") }
            if png == referenceImagePNG { return self }
            return try replacingItem(at: index, with: png)
        }
        guard let png else { return self }
        guard items.count < 10_000, bytes.count - payloadOffset <= 256 * 1024 * 1024 - png.count else {
            throw DocumentError.limitExceeded
        }
        let xml = try Self.xml(header, root: "ds3")
        let asset = XMLElement(name: "asset")
        for (name, value) in [
            ("name", "canvas.png"), ("offset", String(bytes.count - payloadOffset)), ("size", String(png.count)),
        ] {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = name
            attribute.stringValue = value
            asset.addAttribute(attribute)
        }
        xml.rootElement()?.addChild(asset)
        var payload = Data(bytes[payloadOffset...])
        payload.append(png)
        return try rebuildingArchive(xml, payload: payload)
    }

    /// Replace or remove one item, preserving all unrelated payload bytes, including gaps and trailing data.
    private func replacingItem(at itemIndex: Int, with replacement: Data?) throws -> Dust3DDocument {
        let (xml, payload) = try replacingItemPayload(at: itemIndex, with: replacement)
        return try rebuildingArchive(xml, payload: payload)
    }

    private func replacingItemPayload(at itemIndex: Int, with replacement: Data?) throws -> (XMLDocument, Data) {
        let old = items[itemIndex].range
        let data = replacement ?? Data()
        let nextPayloadCount = bytes.count - payloadOffset - old.count + data.count
        guard nextPayloadCount <= 256 * 1024 * 1024 else { throw DocumentError.limitExceeded }
        let delta = data.count - old.count
        let xml = try Self.xml(header, root: "ds3")
        let elements = (xml.rootElement()?.children ?? []).compactMap { $0 as? XMLElement }
        for (index, item) in items.enumerated() {
            if index == itemIndex {
                if replacement != nil {
                    elements[index].attribute(forName: "size")?.stringValue = String(data.count)
                } else {
                    elements[index].detach()
                }
            } else if item.range.lowerBound >= old.upperBound {
                elements[index].attribute(forName: "offset")?.stringValue = String(item.range.lowerBound + delta)
            } else if item.range.isEmpty && old.contains(item.range.lowerBound) {
                // Empty items have no overlapping bytes, but their anchors must remain in bounds after shrinkage.
                elements[index].attribute(forName: "offset")?.stringValue = String(
                    min(item.range.lowerBound, old.lowerBound + data.count))
            }
        }
        var payload = Data(bytes[payloadOffset...])
        payload.replaceSubrange(old, with: data)
        return (xml, payload)
    }

    private func rebuildingArchive(_ xml: XMLDocument, payload: Data) throws -> Dust3DDocument {
        let header = xml.xmlData(options: [.nodePreserveAll])
        guard header.count <= 1024 * 1024 else { throw DocumentError.limitExceeded }
        let start = Data([0xD3, 0x3D]) + Data("DUST3D 1.0 xml ".utf8)
        let offset = start.count + 12 + header.count
        guard offset <= 256 * 1024 * 1024 - payload.count else { throw DocumentError.limitExceeded }
        var result = try Dust3DDocument(data: start + Data(String(format: "%010d\r\n", offset).utf8) + header + payload)
        result.graphOrder = graphOrder.reconciled(with: try Self.xml(result.modelXML, root: "canvas"))
        return result
    }

    /// Copy selected graph objects and their linked-profile dependencies into a bounded fragment.
    /// Unknown attached fields and all archive assets are retained; canvas-global objects are excluded.
    public func copyingNodes(_ ids: Set<String>) throws -> NodeClipboard {
        let model = try Self.xml(modelXML, root: "canvas")
        try NodeClipboardMutation.extract(ids, model: model, contents: editorContents())
        return try NodeClipboard(
            document: replacingModel(model.xmlData(options: [.nodePreserveAll])), selectedNodeIDs: ids)
    }

    private func mergingAssets(
        from source: Dust3DDocument, namespaceBudget: inout DocumentXML.NamespaceBudget
    ) throws -> Dust3DDocument {
        let xml = try Self.xml(header, root: "ds3")
        let sourceXML = try Self.xml(source.header, root: "ds3")
        let destinationElements = (xml.rootElement()?.children ?? []).compactMap { $0 as? XMLElement }
        let sourceElements = (sourceXML.rootElement()?.children ?? []).compactMap { $0 as? XMLElement }
        let existingByName = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.name, $0.offset) })
        var payload = Data(bytes[payloadOffset...])
        var changed = false
        for (index, item) in source.items.enumerated() where index != source.modelIndex {
            if let existingIndex = existingByName[item.name] {
                let existing = items[existingIndex]
                func metadata(_ element: XMLElement) throws -> String {
                    try namespaceBudget.preserve(element)
                    let copy = element.copy() as? XMLElement
                    copy?.removeAttribute(forName: "offset")
                    return copy?.xmlString(options: [.nodePreserveAll]) ?? ""
                }
                guard existingIndex != modelIndex, existing.type == item.type,
                    bytes[(payloadOffset + existing.range.lowerBound)..<(payloadOffset + existing.range.upperBound)]
                        == source.bytes[
                            (source.payloadOffset + item.range.lowerBound)..<(source.payloadOffset
                                + item.range.upperBound)],
                    try metadata(destinationElements[existingIndex]) == metadata(sourceElements[index])
                else { throw DocumentError.conflictingAsset(item.name) }
                continue
            }
            try namespaceBudget.preserve(sourceElements[index])
            guard payload.count <= 256 * 1024 * 1024 - item.range.count,
                let copy = sourceElements[index].copy() as? XMLElement
            else { throw DocumentError.limitExceeded }
            copy.attribute(forName: "offset")?.stringValue = String(payload.count)
            xml.rootElement()?.addChild(copy)
            payload.append(
                source.bytes[
                    (source.payloadOffset + item.range.lowerBound)..<(source.payloadOffset + item.range.upperBound)])
            changed = true
        }
        guard changed else { return self }
        let header = xml.xmlData(options: [.nodePreserveAll])
        let start = Data([0xd3, 0x3d]) + Data("DUST3D 1.0 xml ".utf8)
        let offset = start.count + 12 + header.count
        guard offset <= 256 * 1024 * 1024 - payload.count else { throw DocumentError.limitExceeded }
        var result = try Dust3DDocument(data: start + Data(String(format: "%010d\r\n", offset).utf8) + header + payload)
        result.graphOrder = graphOrder.reconciled(with: try Self.xml(result.modelXML, root: "canvas"))
        return result
    }

    /// Read the first live incident edge in Qt's process-local ordering, independently of archive XML order.
    /// - Parameter nodeID: Existing exact node identity.
    /// - Returns: Nil for an isolated node; retained edge metadata otherwise.
    /// - Throws: `missingNode` or invalid graph errors. Example: `try document.firstIncidentEdge(nodeID: anchorID)`.
    public func firstIncidentEdge(nodeID: String) throws -> DocumentEdge? {
        let contents = try editorContents()
        guard contents.nodes.contains(where: { $0.id == nodeID }) else { throw DocumentError.missingNode(nodeID) }
        guard let first = graphOrder.incident[nodeID]?.first else { return nil }
        guard let edge = contents.edges.first(where: { $0.id == first }), edge.fromID == nodeID || edge.toID == nodeID
        else {
            throw DocumentError.invalidNode
        }
        return edge
    }

    /// Whether this full selection produces at least one safe reduction against the evolving graph.
    /// - Parameter ids: Exact selected identities; degree-ineligible and absent nodes are skipped.
    /// - Returns: False for a no-op or a batch rejected by the same validation as execution. Archive bytes are unchanged.
    /// - Example: `document.canReduceNodes(Array(selection))`.
    public func canReduceNodes(_ ids: [String]) -> Bool {
        guard ids.count <= 10_000, ids.contains(where: { graphOrder.incident[$0]?.count == 2 }) else {
            return false
        }
        do {
            let model = try Self.xml(modelXML, root: "canvas")
            var order = graphOrder
            return try NodeReduction.apply(ids, model: model, contents: editorContents(), order: &order)
        } catch { return false }
    }

    /// Whether an edge can currently accept a midpoint, without allocating identities or changing the archive.
    /// - Parameter id: Exact retained edge identity.
    /// - Returns: False for malformed geometry, read-only ownership, invalid topology or exhausted graph quotas.
    /// - Example: `document.canInsertEdgeMidpoint(id: "edge")`.
    public func canInsertEdgeMidpoint(id: String) -> Bool {
        canInsertEdgeMidpoints(ids: [id])
    }

    /// Inspect full-batch midpoint eligibility using one graph/XML index and aggregate node/edge quotas.
    /// - Parameter ids: Unique explicit original edge identities.
    /// - Returns: False for empty, duplicate, read-only, malformed or over-quota batches. No identities are allocated.
    /// - Example: `document.canInsertEdgeMidpoints(ids: Array(selectedEdgeIDs))`.
    public func canInsertEdgeMidpoints(ids: [String]) -> Bool {
        guard !ids.isEmpty else { return false }
        do {
            let contents = try editorContents()
            let model = try Self.xml(modelXML, root: "canvas")
            _ = try EdgeMidpoints.sources(ids: ids, model: model, contents: contents)
            return true
        } catch { return false }
    }

    /// Inspect the editable graph once, retaining source ordering and stable IDs.
    public func editorContents() throws -> DocumentContents {
        try editorContents(in: Self.xml(modelXML, root: "canvas"))
    }

    private func editorContents(in xml: XMLDocument) throws -> DocumentContents {
        let partContainers = xml.rootElement()?.elements(forName: "parts") ?? []
        let edgeContainers = xml.rootElement()?.elements(forName: "edges") ?? []
        guard partContainers.count <= 1, edgeContainers.count <= 1 else { throw DocumentError.invalidNode }
        var parts: [String: DocumentPart] = [:]
        var orderedParts: [DocumentPart] = []
        func isTrue(_ value: String?) -> Bool { value == "true" || value == "True" || value == "1" }
        let partElements = partContainers.first?.elements(forName: "part") ?? []
        guard partElements.count <= 10_000 else { throw DocumentError.limitExceeded }
        let elements = try Self.nodes(xml)
        guard elements.count <= 10_000 else { throw DocumentError.limitExceeded }
        let cutFaceReferenceCounts = CutFaceLinks.referenceCounts(parts: partElements, nodes: elements)
        for (index, part) in partElements.enumerated() {
            guard let id = part.attribute(forName: "id")?.stringValue, !id.isEmpty, parts[id] == nil else {
                throw DocumentError.invalidNode
            }
            let visible = part.attribute(forName: "visible").map { isTrue($0.stringValue) } ?? true
            let value = DocumentPart(
                id: id, name: part.attribute(forName: "name")?.stringValue ?? "", index: index,
                isVisible: visible, isLocked: isTrue(part.attribute(forName: "locked")?.stringValue),
                isDisabled: isTrue(part.attribute(forName: "disabled")?.stringValue),
                modifiers: PartModifiers.values(part), deformationScales: PartDeformation.scales(part),
                isDeformationUnified: PartDeformation.unified(part), cutFace: PartCutFace.selection(part),
                cutRotation: PartCutFace.rotation(part), target: PartTargetMetadata.value(part),
                isLoopInteriorFilled: PartLoopInterior.value(part), materials: PartMaterial.values(part),
                cutFaceReferenceCount: cutFaceReferenceCounts[id, default: 0],
                xMirrored: PartMirrorMetadata.value(part))
            parts[id] = value
            orderedParts.append(value)
        }
        let nodes = try elements.enumerated().map { index, node -> DocumentNode in
            guard let id = node.attribute(forName: "id")?.stringValue else { throw DocumentError.invalidNode }
            let partID = node.attribute(forName: "partId")?.stringValue
            if let partID, parts[partID] == nil { throw DocumentError.invalidNode }
            let part = partID.flatMap { parts[$0] }
            let name = node.attribute(forName: "name")?.stringValue ?? ""
            return DocumentNode(
                id: id, title: name.isEmpty ? "Node \(index + 1)" : name, partID: partID,
                value: try Self.decodeNode(node), isVisible: part?.isEditVisible ?? true,
                isEditable: part?.isEditable ?? true, deformation: NodeDeformation(node))
        }
        let ids = Set(nodes.map(\.id))
        var edgeIDs = Set<String>()
        let edges = try (edgeContainers.first?.elements(forName: "edge") ?? []).map { edge -> DocumentEdge in
            guard let id = edge.attribute(forName: "id")?.stringValue, edgeIDs.insert(id).inserted,
                let from = edge.attribute(forName: "from")?.stringValue,
                let to = edge.attribute(forName: "to")?.stringValue,
                ids.contains(from), ids.contains(to)
            else { throw DocumentError.invalidNode }
            return DocumentEdge(
                id: id, fromID: from, toID: to,
                boneName: edge.attribute(forName: "boneName")?.stringValue ?? "",
                partID: edge.attribute(forName: "partId")?.stringValue)
        }
        guard edges.count <= 20_000 else { throw DocumentError.limitExceeded }
        return DocumentContents(
            nodes: nodes, edges: edges, parts: orderedParts, origin: xml.rootElement().flatMap(Self.decodeOrigin),
            rigSettings: DocumentRigSettings(root: xml.rootElement()))
    }

    /// Construct a valid blank document for a native untitled document window.
    public static func emptyArchive() -> Data {
        let model = Data(
            "<canvas originX='0.5' originY='0.5' originZ='0.5'><nodes/><edges/><parts/><components/></canvas>".utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
    }

    private static func unsigned(_ text: String?) -> Int? {
        guard let text, !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return Int(text)
    }

    private static func nodes(_ xml: XMLDocument) throws -> [XMLElement] {
        let containers = xml.rootElement()?.elements(forName: "nodes") ?? []
        guard containers.count <= 1 else { throw DocumentError.invalidNode }
        return containers.first?.elements(forName: "node") ?? []
    }

    private static func findNode(_ id: String, in xml: XMLDocument) throws -> XMLElement {
        guard let node = try nodes(xml).first(where: { $0.attribute(forName: "id")?.stringValue == id }) else {
            throw DocumentError.missingNode(id)
        }
        return node
    }

    private static func xml(_ data: Data, root: String, preserveSourceSpelling: Bool = true) throws -> XMLDocument {
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0"),
            !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY")
        else { throw DocumentError.invalidXML }
        let delegate = XMLDepthValidator()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.exceeded else { throw DocumentError.invalidXML }
        do {
            let options: XMLNode.Options =
                preserveSourceSpelling
                ? [.nodePreserveAll, .nodeLoadExternalEntitiesNever]
                : [.nodePreserveWhitespace, .nodeLoadExternalEntitiesNever]
            let document = try XMLDocument(data: data, options: options)
            guard document.rootElement()?.name == root else { throw DocumentError.invalidXML }
            return document
        } catch { throw DocumentError.invalidXML }
    }
}

private final class XMLDepthValidator: NSObject, XMLParserDelegate {
    private var depth = 0
    private var count = 0
    var exceeded = false

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        depth += 1
        count += 1
        if depth > 128 || count > 100_000 {
            exceeded = true
            parser.abortParsing()
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        depth -= 1
    }
}
