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
outward from a chain endpoint) or New Part. Connect to… and Disconnect edit edges in the
selected node’s inspector. Delete Node removes its incident edges in one undo
step. Part locks and visibility are enforced. Connect accepts editable endpoints across parts, retaining the selected node’s part settings and consuming the target part’s leaf settings. Undo restores both parts. Interior nodes, duplicate/self edges, unsupported branches and cyclic linked profiles are rejected. Full modeling inspectors remain later milestones. Unsupported mesh assets remain preserved
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

Multi-node selection is transient and per window. Use sidebar Command/Shift selection, canvas Command-click, or Canvas → Select All Nodes (Command-Shift-A). Drag a selected node to move its editable group, or enter relative offsets in the group inspector. Group deletion removes incident edges; movement and deletion each take one undo step. Read-only nodes remain unchanged. See [selection verification](../../docs/selection-verification.md). Drag empty canvas to marquee-select visible node centers; Shift-drag adds to selection. The group inspector scales positions around the editable-node centroid and radii independently using positive factors. Identity scaling preserves original geometry exactly. Native clipboard commands are described below; remaining transforms stay in the port plan. See [tools verification](../../docs/selection-tools-verification.md) for evidence and the unverified Shift-drag routing check.

Canvas and inspector transform menus provide Front/Side quarter turns, X/Y/Z flips, and X/Z exchange. Rotations/flips honor movement locks; the explicit X/Z exchange ignores axis locks, matching Qt, and retains part read-only protection. Reverse Selected Edges acts on edges with both endpoints selected/editable. The single-node inspector shows directed edge menus with Reverse/Disconnect actions. See [transform verification](../../docs/graph-transform-verification.md).

Disconnecting edges or deleting nodes now splits affected parts into connected groups in the same undo step, keeping generated pieces previewable and copying part/component metadata. The largest group keeps the original identity; other groups receive fresh UUIDs. Connect can rejoin editable endpoints across those parts. Add Node is disabled for interior/read-only nodes or multiple selection; New Part remains independently available. See [splitting verification](../../docs/part-splitting-verification.md).

See [joining verification](../../docs/part-joining-verification.md) for source-settings semantics, namespace/metadata coverage and native save/reopen evidence.


Use Edit → Cut/Copy/Paste (Command-X/C/V), or the inspector’s Clipboard menu, to transfer nodes between windows. Command-A selects all field text while editing, or all nodes from the canvas/sidebar; Canvas → Select All Nodes also retains Command-Shift-A. Native text fields keep their normal clipboard behavior. Copy does not edit the file or undo history. Cut writes successfully before removing only editable selected nodes, preserving read-only nodes and grouping removal/partitioning into one undo step.

Paste uses fresh graph identities, retains part/component style, known profile dependencies and all embedded assets, and selects only explicitly copied nodes. Disconnected copied groups become separate parts in the same undo step, including new readonly copies. Existing readonly parts cannot be modified by construction plans. Initial same-document paste moves 0.04 on Y/Z; external paste starts at original coordinates. Repeated pastes advance another 0.04, and Open resets this transient placement state. Undo/redo preserves committed IDs/bytes; selection and placement remain transient.

The native clipboard format includes **all embedded source assets**, because opaque fields may reference them, and may be large. Same-name incompatible destination assets reject atomically. It currently transfers between native editor windows/apps using a private versioned type; Qt snapshot-text clipboard interchange is a separate adapter task. `.ds3` save/open remains the document interchange path. See [native clipboard verification](../../docs/native-clipboard-verification.md) for tests and native save/reopen evidence.

Node Paste uses the system’s asynchronous PasteButton/Core Transferable API, with the clipboard type exported by the generated Info.plist. The document actor validates the delivered data. For isolated packaging checks, use `DUST3D_APP_OUTPUT_DIR=/private/tmp/dust3d-package-qa ./script/build_and_run.sh --editor --build-only`; this keeps the default app bundle intact.

Preview generation retains the last successful mesh during updates and generation failures, labels it as stale, and shows the original failure with Retry Preview. Edits, undo/redo and saving remain available; retry only regenerates derived output. Empty documents and replacement documents clear retained geometry. Renderer errors remain separate because a failed Metal view cannot display retained geometry. See [the preview state decision](../../docs/adr/0013-resilient-editor-preview.md).
