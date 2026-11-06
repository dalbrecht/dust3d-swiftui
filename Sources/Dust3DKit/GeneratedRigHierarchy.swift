import Foundation

package enum GeneratedRigHierarchyError: Error, Equatable, LocalizedError {
    case invalidJointCount
    case invalidParent
    case cyclicParents

    package var errorDescription: String? {
        switch self {
        case .invalidJointCount: "Generated rig hierarchy exceeds the 256-joint limit."
        case .invalidParent: "Generated rig hierarchy contains an invalid parent index."
        case .cyclicParents: "Generated rig hierarchy contains a parent cycle."
        }
    }
}

/// A forest of original source indices into the supplied generated joints.
/// Roots and siblings retain source order; names, geometry and placement never
/// determine identity or membership. The generation epoch remains the caller's.
package struct GeneratedRigHierarchy: Sendable, Equatable {
    package struct Node: Sendable, Equatable, Identifiable {
        package let index: Int
        package let children: [Node]?
        package var id: Int { index }
    }

    package let roots: [Node]

    private enum Visit: Equatable {
        case unseen
        case active
        case finished
    }

    /// Validate a bounded resolved parent forest and build it without recursive
    /// traversal. Forward parents and multiple roots are supported. Empty input
    /// has no roots; leaves have nil children. Cancellation never publishes a
    /// partial hierarchy, and malformed parents are not silently made roots.
    package init(joints: [GeneratedRigJoint]) throws {
        try Task.checkCancellation()
        guard joints.count <= 256 else { throw GeneratedRigHierarchyError.invalidJointCount }
        var children = Array(repeating: [Int](), count: joints.count)
        var rootIndices: [Int] = []
        for (index, joint) in joints.enumerated() {
            try Task.checkCancellation()
            if let parent = joint.parentIndex {
                guard joints.indices.contains(parent), parent != index else {
                    throw GeneratedRigHierarchyError.invalidParent
                }
                children[parent].append(index)
            } else {
                rootIndices.append(index)
            }
        }

        // Visit every component, including cycles disconnected from valid roots.
        // Postorder lets the value tree reuse completed child values without
        // recursive construction or force-unwrapping optional placeholders.
        var visits = Array(repeating: Visit.unseen, count: joints.count)
        var postorder: [Int] = []
        for start in joints.indices {
            try Task.checkCancellation()
            if visits[start] != .unseen { continue }
            var stack: [(index: Int, exiting: Bool)] = [(start, false)]
            while let frame = stack.popLast() {
                try Task.checkCancellation()
                let index = frame.index
                if frame.exiting {
                    visits[index] = .finished
                    postorder.append(index)
                    continue
                }
                switch visits[index] {
                case .finished: continue
                case .active: throw GeneratedRigHierarchyError.cyclicParents
                case .unseen: visits[index] = .active
                }
                stack.append((index, true))
                for child in children[index].reversed() {
                    try Task.checkCancellation()
                    stack.append((child, false))
                }
            }
        }

        var nodes = joints.indices.map { Node(index: $0, children: nil) }
        for index in postorder {
            try Task.checkCancellation()
            if !children[index].isEmpty {
                let childNodes = children[index].map { nodes[$0] }
                nodes[index] = Node(index: index, children: childNodes)
            }
        }
        let roots = rootIndices.map { nodes[$0] }
        try Task.checkCancellation()
        self.roots = roots
    }
}
