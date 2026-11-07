import Dust3DDocument
import Foundation

/// An isolation action cannot infer ownership from ambiguous or opaque links.
public enum CanvasPartIsolationError: Error, Equatable, Sendable, LocalizedError {
    case staleTarget
    case ambiguousTarget
    case missingMembership
    case unsupportedMembership(String)

    public var errorDescription: String? {
        switch self {
        case .staleTarget: "The document, selection or editing constraints changed. Choose the action again."
        case .ambiguousTarget: "Choose one component or graph owner to hide other parts in the canvas."
        case .missingMembership: "The target has no unambiguous existing component and part membership."
        case .unsupportedMembership(let cause): "Canvas part membership is unavailable: \(cause)"
        }
    }
}

/// Captures Qt's hide-others/show-all canvas operation without changing mesh flags.
/// Component traversal stops at a part link, including legacy hybrid components.
public struct CanvasPartIsolationTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    private let plannedCommands: [DocumentCommand]
    private let issue: CanvasPartIsolationError?
    public let title: String
    public let restoresAll: Bool

    public var isAvailable: Bool { issue == nil && !plannedCommands.isEmpty }
    public var unavailableReason: String? {
        if let issue { return issue.localizedDescription }
        guard !isAvailable else { return nil }
        return restoresAll
            ? "All parts are already visible in the canvas."
            : "All parts are already hidden in the canvas."
    }

    /// Capture explicit rendered ownership or resolve the current single owner.
    /// - Parameters:
    ///   - snapshot: Source document, selection and constraint epoch.
    ///   - componentID: Optional exact component identity; excludes partID.
    ///   - partID: Optional exact part identity requiring one owning component.
    ///   - showAll: Restore all canvas visibility independently of selection or hierarchy.
    public init(
        snapshot: EditorSnapshot, componentID: String? = nil, partID: String? = nil, showAll: Bool = false
    ) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        do {
            let plan = try Self.plan(snapshot: snapshot, componentID: componentID, partID: partID, showAll: showAll)
            restoresAll = plan.visible
            title = plan.visible ? "Show All Parts in Canvas" : "Hide Other Parts in Canvas"
            plannedCommands =
                plan.ids.isEmpty ? [] : [.setPartsState(ids: plan.ids, property: .visible, value: plan.visible)]
            issue = nil
        } catch let cause {
            restoresAll = showAll
            title = showAll ? "Show All Parts in Canvas" : "Hide Other Parts in Canvas"
            plannedCommands = []
            issue = cause
        }
    }

    /// Capture every part's canvas visibility independently of selection or hierarchy.
    /// This plans one atomic visibility-only edit; it does not change the document
    /// until the existing actor operation applies the captured commands.
    /// - Parameter snapshot: The source document, selection and constraint epoch.
    /// - Returns: A Hide All target, unavailable without history changes when already hidden.
    public static func hidingAll(in snapshot: EditorSnapshot) -> Self { Self(hidingAllIn: snapshot) }

    private init(hidingAllIn snapshot: EditorSnapshot) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        let ids = snapshot.parts.contains(where: \.isVisible) ? snapshot.parts.map(\.id) : []
        plannedCommands = ids.isEmpty ? [] : [.setPartsState(ids: ids, property: .visible, value: false)]
        issue = nil
        title = "Hide All Parts in Canvas"
        restoresAll = false
    }

    /// Captured actions never acquire a later selection, even after Undo or ABA changes.
    public func isCurrent(in snapshot: EditorSnapshot) -> Bool { context.isCurrent(in: snapshot) }

    func commands(in snapshot: EditorSnapshot) throws -> [DocumentCommand] {
        guard isCurrent(in: snapshot) else { throw CanvasPartIsolationError.staleTarget }
        if let issue { throw issue }
        return plannedCommands
    }

    private struct Plan {
        let ids: [String]
        let visible: Bool
    }

    private static func plan(
        snapshot: EditorSnapshot, componentID: String?, partID: String?, showAll: Bool
    ) throws(CanvasPartIsolationError) -> Plan {
        guard componentID == nil || partID == nil else { throw .ambiguousTarget }
        if showAll { return showAllPlan(snapshot.parts) }
        if let cause = snapshot.componentTree.failureDescription { throw .unsupportedMembership(cause) }
        // Snapshot readers already reject duplicate identities. Use literal UTF8
        // keys here so a canonical-equivalent spelling cannot acquire an owner.
        let components = Dictionary(
            uniqueKeysWithValues: snapshot.componentTree.rows.map { (Data($0.id.utf8), $0.component) })
        let parts = Dictionary(uniqueKeysWithValues: snapshot.parts.map { (Data($0.id.utf8), $0) })
        let root: Data
        if let componentID {
            root = Data(componentID.utf8)
        } else if let partID {
            root = try owner(of: Data(partID.utf8), components: components, parts: parts)
        } else if !snapshot.selectedComponentIDs.isEmpty {
            guard snapshot.selectedComponentIDs.count == 1, let selected = snapshot.selectedComponentIDs.first else {
                throw .ambiguousTarget
            }
            root = Data(selected.utf8)
        } else if let selected = snapshot.selectedPartID {
            root = try owner(of: Data(selected.utf8), components: components, parts: parts)
        } else {
            root = try owner(of: selectedGraphPart(snapshot), components: components, parts: parts)
        }
        guard components[root] != nil else { throw .missingMembership }
        var inside: Set<Data> = []
        var pending = [root]
        // ComponentTree comes from a validated, bounded XML forest. A supported
        // part link terminates traversal even if that component has child XML.
        while let key = pending.popLast() {
            guard let component = components[key] else {
                throw .unsupportedMembership("A descendant component is missing.")
            }
            if component.linkDataType == "partId" {
                guard let id = component.linkData, !id.isEmpty, parts[Data(id.utf8)] != nil else {
                    throw .unsupportedMembership("A component refers to a missing part.")
                }
                inside.insert(Data(id.utf8))
            } else {
                guard component.isGroup else {
                    throw .unsupportedMembership("A component uses an unsupported part link.")
                }
                pending.append(contentsOf: component.childIDs.reversed().map { Data($0.utf8) })
            }
        }
        guard !inside.isEmpty else { throw .missingMembership }
        let outside = snapshot.parts.filter { !inside.contains(Data($0.id.utf8)) }
        if outside.contains(where: \.isVisible) { return Plan(ids: outside.map(\.id), visible: false) }
        return showAllPlan(snapshot.parts)
    }

    private static func showAllPlan(_ parts: [DocumentPart]) -> Plan {
        Plan(ids: parts.contains(where: { !$0.isVisible }) ? parts.map(\.id) : [], visible: true)
    }

    private static func owner(
        of partID: Data, components: [Data: DocumentComponent], parts: [Data: DocumentPart]
    ) throws(CanvasPartIsolationError) -> Data {
        guard parts[partID] != nil else { throw .missingMembership }
        let owners = components.filter {
            $0.value.linkDataType == "partId" && $0.value.linkData.map { Data($0.utf8) } == partID
        }
        guard !owners.isEmpty else { throw .missingMembership }
        guard owners.count == 1, let owner = owners.first else { throw .ambiguousTarget }
        return owner.key
    }

    private static func selectedGraphPart(_ snapshot: EditorSnapshot) throws(CanvasPartIsolationError) -> Data {
        let nodes = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { (Data($0.id.utf8), $0) })
        let edges = Dictionary(uniqueKeysWithValues: snapshot.edges.map { (Data($0.id.utf8), $0) })
        var owners: Set<Data> = []
        for id in snapshot.selectedIDs {
            guard let node = nodes[Data(id.utf8)], let owner = node.partID, !owner.isEmpty else {
                throw .missingMembership
            }
            owners.insert(Data(owner.utf8))
        }
        for id in snapshot.selectedEdgeIDs {
            guard let edge = edges[Data(id.utf8)], let owner = edge.partID, !owner.isEmpty else {
                throw .missingMembership
            }
            owners.insert(Data(owner.utf8))
        }
        guard !owners.isEmpty else { throw .missingMembership }
        guard owners.count == 1, let owner = owners.first else { throw .ambiguousTarget }
        return owner
    }
}
