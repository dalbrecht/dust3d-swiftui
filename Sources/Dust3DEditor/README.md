# Dust3D Editor

Separate macOS 14+ SwiftUI document app. Run from the repository root with
`./script/build_and_run.sh --editor`, or package with `--editor --build-only`.

Open an existing `.ds3`, select a node in the list or canvas, drag it in Front
(X/Y) or Side (Z/Y), or edit X/Y/Z/radius and press Apply. Undo/redo operates on
committed edits. Native document scenes provide Open, Save, Save As and unsaved
close handling. Each window has independent state. Locked/hidden parts cannot
be changed. The mesh preview uses the same Qt-free engine and Metal renderer as
the standalone viewer.

New documents start empty. Use the + menu to Add Node (extend the selected node
in the same part) or New Part. Connect to… and Disconnect edit edges in the
selected node’s inspector. Delete Node removes its incident edges in one undo
step. Part locks and visibility are enforced. Connecting different parts and
duplicate/self edges is rejected. Full modeling inspectors remain later milestones. Unsupported mesh assets remain preserved
even when the preview cannot display them. The standalone viewer remains read-only.

Development: `make ci`. No Qt dependency, hand-maintained Xcode project or extra
Swift package is required beyond the existing pinned engine dependency.

Quit the editor normally before using the run script again; it refuses to kill a
running editor with potentially unsaved document edits. `--build-only` does not launch.

Use the canvas Locks controls or Canvas menu to lock X, Y, Z or Radius.
Command-Option-X/Y/Z/R toggles the corresponding lock. Locks constrain new
coordinate/radius edits and the drag preview; they do not block undo/redo or
node creation/deletion. Locking an inspector field resets its unapplied draft.
Settings belong to the current window and are not saved in the `.ds3` archive.

Multi-node selection is transient and per window. Use sidebar Command/Shift selection, canvas Command-click, or Canvas → Select All Nodes (Command-Shift-A). Drag a selected node to move its editable group, or enter relative offsets in the group inspector. Group deletion removes incident edges; movement and deletion each take one undo step. Read-only nodes remain unchanged. See [selection verification](../../docs/selection-verification.md). Drag empty canvas to marquee-select visible node centers; Shift-drag adds to selection. The group inspector scales positions around the editable-node centroid and radii independently using positive factors. Identity scaling preserves original geometry exactly. Clipboard and other transforms remain pending. See [tools verification](../../docs/selection-tools-verification.md) for evidence and the unverified Shift-drag routing check.
