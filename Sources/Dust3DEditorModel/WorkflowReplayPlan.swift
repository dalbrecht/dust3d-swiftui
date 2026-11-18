import Dust3DDocument
import Foundation

/// Qt's replay speed setting is linear in delay, from about three seconds to 50 ms.
package enum WorkflowReplaySpeed {
    package static let range = 1...20
    package static let initial = 11

    package static func intervalMilliseconds(for setting: Int) -> Int {
        let bounded = min(range.upperBound, max(range.lowerBound, setting))
        return 3150 - bounded * 155
    }
}

/// Reconstruct the source graph in component order without mutating the source document.
package struct WorkflowReplayPlan: Sendable {
    package enum Step: Equatable, Sendable {
        case referenceImage
        case node(id: String, incomingEdgeID: String?)
        case edge(id: String)
        case restoreEdgeDirections(ids: [String])
        case property(ReplayProperty)
        case createGroup(id: String, name: String)
        case movePart(id: String, groupName: String)
        case addAnimation(id: String, name: String)
        case setRigType(String)
        case assignBone(name: BoneNameIdentity, edgeIDs: [String])
    }

    package let steps: [Step]
    package let bounds: CanvasBounds
    package let animationMetadataError: String?
    private let graph: DocumentContents
    private let enabledNodes: [String: DocumentNode]
    private let finalMeshStep: Int

    /// Return only the property just applied at this step, without reconstructing its frame.
    package func appliedProperty(after completedSteps: Int) -> ReplayProperty? {
        guard completedSteps > 0, completedSteps <= steps.count,
            case .property(let property) = steps[completedSteps - 1]
        else { return nil }
        return property
    }

    package func frame(after completedSteps: Int) -> (nodes: [DocumentNode], edges: [DocumentEdge]) {
        var nodes = Set<String>()
        var edges = Set<String>()
        for step in steps.prefix(max(0, completedSteps)) {
            switch step {
            case .node(let id, let incoming):
                nodes.insert(id)
                if let incoming { edges.insert(incoming) }
            case .edge(let id):
                edges.insert(id)
            case .referenceImage, .property, .createGroup, .movePart, .restoreEdgeDirections,
                .setRigType, .assignBone, .addAnimation:
                break
            }
        }
        let reversed = pendingReversals(after: completedSteps)
        let pendingBones = pendingBoneAssignments(after: completedSteps)
        let visibleEdges = graph.edges.filter { edges.contains($0.id) }.map { edge in
            let isReversed = reversed.contains(edge.id)
            let boneName = pendingBones.contains(edge.id) ? "" : edge.boneName
            return DocumentEdge(
                id: edge.id, fromID: isReversed ? edge.toID : edge.fromID,
                toID: isReversed ? edge.fromID : edge.toID, boneName: boneName, partID: edge.partID)
        }
        let pendingEnabledParts = Set(
            steps.dropFirst(max(0, completedSteps)).compactMap { step -> String? in
                guard case .property(let property) = step, property.owner == .part,
                    property.fields.contains(where: { $0.name == "disabled" })
                else { return nil }
                return property.id
            })
        let visibleNodes = graph.nodes.filter { nodes.contains($0.id) }.map { node in
            guard let partID = node.partID, pendingEnabledParts.contains(partID) else { return node }
            return enabledNodes[node.id] ?? node
        }
        return (visibleNodes, visibleEdges)
    }

    private func pendingReversals(after completedSteps: Int) -> Set<String> {
        var reversed = Set<String>()
        for case .restoreEdgeDirections(let ids) in steps.dropFirst(max(0, completedSteps)) {
            reversed.formUnion(ids)
        }
        return reversed
    }

    private func pendingBoneAssignments(after completedSteps: Int) -> Set<String> {
        var pending = Set<String>()
        for case .assignBone(_, let edgeIDs) in steps.dropFirst(max(0, completedSteps)) {
            pending.formUnion(edgeIDs)
        }
        return pending
    }

    package func showsReferenceImage(after completedSteps: Int) -> Bool {
        completedSteps > 0 && steps.first == .referenceImage
    }

    package func bounds(referenceImageAspectRatio: Double) -> CanvasBounds {
        CanvasBounds(
            nodes: graph.nodes.map { enabledNodes[$0.id] ?? $0 },
            referenceImageAspectRatio: referenceImageAspectRatio, origin: graph.origin)
    }

    /// Animation metadata changes the replay narrative without changing the static preview.
    package func meshStep(after completedSteps: Int) -> Int {
        min(max(0, completedSteps), finalMeshStep)
    }

    package func meshPreviewDocument(at step: Int, source: Dust3DDocument) throws -> Dust3DDocument {
        if step == finalMeshStep { return source }
        return try previewDocument(after: step, source: source)
    }

    package func previewDocument(after completedSteps: Int, source: Dust3DDocument) throws -> Dust3DDocument {
        guard completedSteps < steps.count else { return source }
        let visible = frame(after: completedSteps)
        var pendingProperties: [ReplayProperty] = []
        var pendingGroups = Set<String>()
        var pendingMoves = Set<String>()
        var pendingRigType = false
        var pendingAnimationIDs = Set<[UInt8]>()
        for step in steps.dropFirst(max(0, completedSteps)) {
            switch step {
            case .property(let property): pendingProperties.append(property)
            case .createGroup(let id, _): pendingGroups.insert(id)
            case .movePart(let id, _): pendingMoves.insert(id)
            case .setRigType: pendingRigType = true
            case .addAnimation(let id, _): pendingAnimationIDs.insert(Array(id.utf8))
            case .referenceImage, .node, .edge, .restoreEdgeDirections, .assignBone: break
            }
        }
        let frame = try source.replayFrame(
            nodeIDs: Set(visible.nodes.map(\.id)), edgeIDs: Set(visible.edges.map(\.id)),
            pendingProperties: pendingProperties, pendingGroupIDs: pendingGroups,
            pendingMoveIDs: pendingMoves, reversedEdgeIDs: pendingReversals(after: completedSteps),
            hidesRigType: pendingRigType, unassignedBoneEdgeIDs: pendingBoneAssignments(after: completedSteps),
            pendingAnimationIDs: pendingAnimationIDs)
        return frame.hasReferenceImage && !showsReferenceImage(after: completedSteps)
            ? try frame.applying(.setReferenceImagePNG(nil)) : frame
    }

    package init(document: Dust3DDocument) throws {
        let graph = try document.editorContents()
        let components = try document.components()
        let nodesByPart = Dictionary(grouping: graph.nodes, by: \.partID)
        let nodes = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard nodes.count == graph.nodes.count else { throw DocumentError.invalidNode }
        var edgesByPart: [String?: [DocumentEdge]] = [:]
        var crossPartEdges: [DocumentEdge] = []
        for edge in graph.edges {
            let fromPart = nodes[edge.fromID]?.partID
            let toPart = nodes[edge.toID]?.partID
            if fromPart == toPart {
                edgesByPart[fromPart, default: []].append(edge)
            } else {
                crossPartEdges.append(edge)
            }
        }

        let properties = try document.replayProperties()
        let nodeProperties = Dictionary(grouping: properties.filter { $0.owner == .node }, by: \.id)
        let partProperties = Dictionary(grouping: properties.filter { $0.owner == .part }, by: \.id)
        let componentProperties = Dictionary(grouping: properties.filter { $0.owner == .component }, by: \.id)
        let linkedComponents = Dictionary(
            grouping: components.compactMap { component in
                component.partID.map { (partID: $0, componentID: component.id) }
            }, by: \.partID)
        var visitedParts = Set<String?>()
        var stagedComponents = Set<String>()
        var deferredProfiles: [String: [ReplayProperty]] = [:]
        var unresolvedProfiles: [ReplayProperty] = []
        var steps: [Step] = document.hasReferenceImage ? [.referenceImage] : []
        steps.reserveCapacity(graph.nodes.count + graph.edges.count + properties.count)
        let partOrder =
            components.compactMap(\.partID).map(Optional.some)
            + graph.parts.map { Optional($0.id) } + [nil]
        func stage(_ property: ReplayProperty, for part: String?) {
            // A linked cross-section needs the target geometry to exist in the frame.
            guard let target = property.profilePartID else {
                steps.append(.property(property))
                return
            }
            if nodesByPart[target] == nil {
                unresolvedProfiles.append(property)
            } else if target == part || !visitedParts.contains(target) {
                deferredProfiles[target, default: []].append(property)
            } else {
                steps.append(.property(property))
            }
        }
        for part in partOrder where visitedParts.insert(part).inserted {
            let firstStep = steps.count
            let reversals = Self.appendSteps(
                nodes: nodesByPart[part] ?? [], edges: edgesByPart[part] ?? [], to: &steps)
            let nodeIDs = steps[firstStep...].compactMap { step -> String? in
                guard case .node(let id, _) = step else { return nil }
                return id
            }
            for id in nodeIDs {
                for property in nodeProperties[id] ?? [] {
                    stage(property, for: part)
                }
            }
            if !reversals.isEmpty { steps.append(.restoreEdgeDirections(ids: reversals)) }
            guard let part else { continue }
            for property in partProperties[part] ?? [] {
                stage(property, for: part)
            }
            for link in linkedComponents[part] ?? [] where stagedComponents.insert(link.componentID).inserted {
                steps.append(contentsOf: (componentProperties[link.componentID] ?? []).map(Step.property))
            }
            if let ready = deferredProfiles.removeValue(forKey: part) {
                steps.append(contentsOf: ready.map(Step.property))
            }
        }
        steps.append(contentsOf: crossPartEdges.map { .edge(id: $0.id) })
        steps.append(contentsOf: unresolvedProfiles.map(Step.property))
        let groupNames = Dictionary(uniqueKeysWithValues: components.filter(\.isGroup).map { ($0.id, $0.name) })
        for component in components {
            if component.isGroup {
                steps.append(.createGroup(id: component.id, name: component.name))
            }
            if !stagedComponents.contains(component.id) {
                steps.append(contentsOf: (componentProperties[component.id] ?? []).map(Step.property))
            }
            if component.partID != nil, let parentID = component.parentID, let groupName = groupNames[parentID] {
                steps.append(.movePart(id: component.id, groupName: groupName))
            }
        }
        let boneAssignments = Dictionary(
            grouping: graph.edges.filter { !$0.boneName.isEmpty }, by: { Array($0.boneName.utf8) })
        if !boneAssignments.isEmpty {
            let rig = graph.rigSettings
            steps.append(.setRigType(rig.rigType?.rawValue ?? rig.sourceRigType ?? DocumentRigType.disabled.rawValue))
            let groups = boneAssignments.values.sorted {
                ($0.first?.boneName ?? "").utf16.lexicographicallyPrecedes(($1.first?.boneName ?? "").utf16)
            }
            for group in groups {
                guard let edge = group.first else { continue }
                steps.append(.assignBone(name: BoneNameIdentity(edge.boneName), edgeIDs: group.map(\.id)))
            }
        }
        finalMeshStep = steps.count
        do {
            for animation in try document.animations() {
                let name = animation.name ?? animation.id
                steps.append(.addAnimation(id: animation.id, name: name))
                let parameters = animation.parameters.filter { $0.name != "surfaceMaterial" }.sorted {
                    $0.name.utf8.lexicographicallyPrecedes($1.name.utf8)
                }
                for parameter in parameters {
                    steps.append(
                        .property(
                            ReplayProperty(
                                owner: .animation, id: animation.id,
                                fields: [.init(name: parameter.name, value: parameter.value)],
                                title: "\(name) — \(parameter.name)", profilePartID: nil)))
                }
            }
            animationMetadataError = nil
        } catch {
            animationMetadataError = error.localizedDescription
        }
        self.steps = steps
        self.graph = graph
        let disabledParts = graph.parts.filter(\.isDisabled).map(\.id)
        let enabled: [String: DocumentNode]
        if disabledParts.isEmpty {
            enabled = [:]
        } else {
            // Cache the staged default-enabled state once, retaining source visibility and locks.
            let initialNodes = try document.applying(
                .setPartsState(ids: disabledParts, property: .disabled, value: false)
            )
            .editorContents().nodes
            enabled = Dictionary(uniqueKeysWithValues: initialNodes.map { ($0.id, $0) })
        }
        enabledNodes = enabled
        bounds = CanvasBounds(nodes: graph.nodes.map { enabled[$0.id] ?? $0 }, origin: graph.origin)
    }

    private static func appendSteps(
        nodes: [DocumentNode], edges: [DocumentEdge], to steps: inout [Step]
    ) -> [String] {
        struct Arrival {
            let node: String
            let edge: String?
            var reversesEdge = false
        }

        var adjacency: [String: [Arrival]] = [:]
        for edge in edges {
            adjacency[edge.fromID, default: []].append(Arrival(node: edge.toID, edge: edge.id))
            adjacency[edge.toID, default: []].append(Arrival(node: edge.fromID, edge: edge.id, reversesEdge: true))
        }
        // A chain starts at its first stored endpoint. A loop has no endpoint.
        let endpoints = nodes.filter { adjacency[$0.id, default: []].count <= 1 }
        var visitedNodes = Set<String>()
        var traversedEdges = Set<String>()
        var reversals: [String] = []
        for node in endpoints + nodes where !visitedNodes.contains(node.id) {
            var pending = [Arrival(node: node.id, edge: nil)]
            while let arrival = pending.popLast() {
                guard visitedNodes.insert(arrival.node).inserted else { continue }
                steps.append(.node(id: arrival.node, incomingEdgeID: arrival.edge))
                if let edge = arrival.edge {
                    traversedEdges.insert(edge)
                    if arrival.reversesEdge { reversals.append(edge) }
                }
                pending.append(contentsOf: adjacency[arrival.node, default: []].reversed())
            }
        }
        for edge in edges where !traversedEdges.contains(edge.id) {
            steps.append(.edge(id: edge.id))
        }
        return reversals
    }
}
