import Dust3DDocument

/// Captures explicit component picks and their common stitching controls.
package struct ComponentStitchingBatchTarget: Sendable {
    private let target: ComponentMeshSelectionTarget
    private let groups: [DocumentComponent]
    private let support: ComponentStitchingBatchSupport

    package var supportsLine: Bool { support.line }
    package var supportsLoop: Bool { support.loop }
    package var supportsCap: Bool { support.cap }
    package var supportsBack: Bool { support.back }
    var ids: [String] { target.ids }

    package init(snapshot: EditorSnapshot) {
        target = ComponentMeshSelectionTarget(snapshot: snapshot)
        let components = snapshot.componentTree.rows.map(\.component)
        groups = snapshot.selectedComponentRows.map(\.component)
        support = ComponentStitchingBatchSupport(
            groups: groups.count > 1 && groups.count == target.count ? groups : [], components: components,
            parts: snapshot.parts)
    }

    package func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        supportsBack && target.isCurrent(in: snapshot)
    }

    package func permits(_ edit: ComponentStitchingEdit) -> Bool {
        if case .scalar = edit { return supportsCap }
        return support.permits(edit)
    }

    package func closure(_ property: ComponentStitchingClosureProperty) -> ComponentMeshSelectionValue<Bool> {
        common { $0.closureValue(property) }
    }

    package var targetSegments: ComponentMeshSelectionValue<Int> { common(\.targetSegments) }

    package func scalar(_ property: ComponentStitchingScalarProperty) -> ComponentMeshSelectionValue<Double> {
        common { $0.scalarValue(property) }
    }

    package var segmentDraftValues: [Int?] { groups.map(\.stitching.targetSegments) }

    package func scalarDraftValues(_ property: ComponentStitchingScalarProperty) -> [Double?] {
        groups.map { $0.stitching.scalarValue(property) }
    }

    private func common<Value: Equatable & Sendable>(
        _ value: (ComponentStitchingSettings) -> Value?
    ) -> ComponentMeshSelectionValue<Value> {
        let values = groups.map { value($0.stitching) }
        if values.contains(where: { $0 == nil }) { return .unsupported }
        return .read(values)
    }
}
