# ADR 0026: Explicit descendant rotation

Status: Accepted

## Decision

Add a separate Rotate Around Selected Node menu in Canvas and the single-node inspector. Require exactly one editable pivot and a complete supported stored document origin. Keep the existing selected-centroid transforms unchanged. Offer clockwise and counterclockwise quarter turns in Front X/Y and Side Z/Y.

Build undirected adjacency once. For a pivot with multiple neighbors, exclude the direct neighbor nearest the stored origin in three dimensions from the initial traversal seeds. Resolve equal distances in source node order. An endpoint seeds its sole neighbor. Traverse with a visited set containing the pivot; a cycle can reach the initially excluded neighbor through another path. This follows the inherited Qt selection algorithm while making ties deterministic.

Rotate reachable editable nodes around the fixed pivot. Traverse through read-only nodes without moving them. Preserve radii, topology, origin, selection, unrelated nodes, unknown XML and assets. Validate every proposed position before applying axis masks, and submit one setNodes transaction. Identity/isolated/fully locked actions preserve redo and create no undo step. Invalid selection, origin or geometry fails atomically.

## Compatibility and consequences

Qt temporarily disables position and read-only locks during descendant rotation. Native tools deliberately honor those locks, consistent with the editor's locked-entity policy. Native zero origin is a valid explicit target; no implicit fuzzy-zero settlement occurs. Positive Y points down in the unrotated Front/Side views. Rotated-profile comparisons remain pending.

The model contains no SwiftUI dependency. Session serialization, preview generation and lossless history use existing boundaries. No core adapter, dependency, pin or C++ convention changes are required. Synthetic cycle/cross-part traversal tests prove command semantics, not support for those topologies in inherited mesh generation. See [verification](../descendant-rotation-verification.md).
