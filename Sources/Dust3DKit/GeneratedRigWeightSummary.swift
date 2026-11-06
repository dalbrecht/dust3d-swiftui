import Foundation

/// Numerical selected weights across admitted body draw corners, grouped as triangles.
/// Repeated corners stay included; these are not counts of original mesh vertices.
package struct GeneratedRigWeightSummary: Sendable, Equatable {
    package let minimumWeight: Float
    package let maximumWeight: Float
    package let influencedTriangleCount: Int
    package let triangleCount: Int
}

package enum GeneratedRigWeightSummaryError: Error, Equatable, LocalizedError {
    case invalidCorrespondence
    case invalidInfluence
    case invalidJointIndex

    package var errorDescription: String? {
        switch self {
        case .invalidCorrespondence: "Generated rig triangle and influence data do not match."
        case .invalidInfluence: "Generated rig contains invalid influence weights."
        case .invalidJointIndex: "Generated rig influence references an invalid joint."
        }
    }
}

extension GeneratedRig {
    /// Summarize one exact UTF8 joint name without changing geometry or stored weights.
    /// Empty/unknown selection returns nil. Range includes every admitted body corner;
    /// a triangle is influenced when any of its three corners has positive selected weight.
    /// Checks copied-data correspondence, finite 0...1 weights, unused-slot sentinels,
    /// source indices and the native bound-weight normalization tolerance of1e-4.
    /// Cancellation is observed before selection, every1024 corners and before return.
    package func weightSummary(selectedBoneName: String) throws -> GeneratedRigWeightSummary? {
        try Task.checkCancellation()
        guard !selectedBoneName.isEmpty,
            let selected = joints.firstIndex(where: { $0.name.utf8.elementsEqual(selectedBoneName.utf8) })
        else { return nil }
        guard let selectedIndex = UInt32(exactly: selected) else {
            throw GeneratedRigWeightSummaryError.invalidJointIndex
        }
        guard !mesh.vertices.isEmpty, mesh.vertices.count.isMultiple(of: 3),
            influences.count == mesh.vertices.count
        else { throw GeneratedRigWeightSummaryError.invalidCorrespondence }
        var minimumWeight = Float.infinity
        var maximumWeight: Float = 0
        var influencedTriangleCount = 0
        var triangleInfluenced = false
        for (index, influence) in influences.enumerated() {
            if index.isMultiple(of: 1024) { try Task.checkCancellation() }
            var selectedWeight: Double = 0
            var totalWeight: Double = 0
            for slot in 0..<4 {
                let weight = influence.weights[slot]
                guard weight.isFinite, weight >= 0, weight <= 1 else {
                    throw GeneratedRigWeightSummaryError.invalidInfluence
                }
                let joint = influence.joints[slot]
                if weight == 0 {
                    guard joint == UInt32.max else { throw GeneratedRigWeightSummaryError.invalidJointIndex }
                } else {
                    guard let sourceIndex = Int(exactly: joint), joints.indices.contains(sourceIndex) else {
                        throw GeneratedRigWeightSummaryError.invalidJointIndex
                    }
                }
                totalWeight += Double(weight)
                if joint == selectedIndex { selectedWeight += Double(weight) }
            }
            guard totalWeight == 0 || abs(totalWeight - 1) <= 0.0001 else {
                throw GeneratedRigWeightSummaryError.invalidInfluence
            }
            let weight = Float(selectedWeight)
            minimumWeight = min(minimumWeight, weight)
            maximumWeight = max(maximumWeight, weight)
            triangleInfluenced = triangleInfluenced || weight > 0
            if index % 3 == 2 {
                if triangleInfluenced { influencedTriangleCount += 1 }
                triangleInfluenced = false
            }
        }
        try Task.checkCancellation()
        return GeneratedRigWeightSummary(
            minimumWeight: minimumWeight, maximumWeight: maximumWeight,
            influencedTriangleCount: influencedTriangleCount, triangleCount: mesh.vertices.count / 3)
    }
}
