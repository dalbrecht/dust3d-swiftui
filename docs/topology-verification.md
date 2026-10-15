# Node and edge topology verification

October 14, 2026. Node/part creation, selected-node chain extension, same-part
edge connection/disconnection and cascading node deletion are implemented.
Creation and its edge form one undo step. Failed transactions retain the prior
archive and selection; deletion clears invalid selection. Undo/redo restores
complete archive snapshots, including the original bytes. Empty part/component
metadata remains preserved when its last node is removed.

`make ci` passes 55 tests, formatting, native builds and both-app Qt-link checks.
New tests began red before API implementation. They cover create/connect/delete,
incident-edge cleanup, exact undo archives, rejected duplicate/self/missing edges,
invalid node inputs, atomic batches and cancellation, hidden/locked guards,
unknown XML values and opaque binary asset retention, selection after topology
undo, actor routing, and generation of a newly created graph through the pinned
native engine. The engine integration test exposed missing blank-document
origins; explicit origins fix new-model generation.

Measured executable-line coverage: document library 524/540 (97.04%), editor model
144/150 (96%), pure editor state 66/66 and undo history 91/91 (100%). Mesh library
remains 66/67 (98.51%). SwiftUI/GPU and inherited C++ are outside these metrics.

Manual native app checks created two connected nodes in a blank document,
disconnected and reconnected the edge, deleted a node, and exercised toolbar
undo/redo through creation and deletion. Disconnected nodes displayed the engine
diagnostic; connecting restored the preview. Saved Topology-native.ds3 to a
disposable temporary directory, quit normally, rebuilt the final app, reopened it
and verified two nodes, the mesh, and fresh history. Final inspector scrolling and
bundle signature/process launch passed. No repository fixture was overwritten.

This slice does not merge/split parts, support arbitrary branching generation,
implement multi-selection/clipboard, or expose all inherited constraints. New Part
creates an independent part; Connect to requires nodes in the same part. Unsupported
graph shapes remain losslessly saveable with explicit preview diagnostics. Qt app
interactive interoperability, older macOS and broad accessibility/performance
checks remain in the full parity plan.
