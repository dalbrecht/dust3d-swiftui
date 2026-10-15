# Dust3D editor model

Swift 6 library for one document’s selection, validated node edits and undo/redo.
`EditorState` is a value-based state machine; `EditorSession` serializes it away
from the UI actor and returns immutable snapshots. Each window owns a session.
`CanvasProjection` maps Front X/Y and Side Z/Y gestures to model coordinates.

Use `try await session.open(data:)`, select a node ID, then `edit(id:position:radius:)`.
Open/edit failures retain the previous state. One edit call is one undo step;
selection does not dirty the archive. Parts marked hidden or locked are read-only.
History bounds and lossless archive preservation come from Dust3DDocument.

No SwiftUI, AppKit, Qt or additional package dependency. Run `make ci` at the repo
root; tests cover command atomicity, undo, locks, projection and actor routing.

`session.apply(commands, selecting:)` commits graph commands as one atomic undo
step; a failed batch preserves document and selection. Deletion clears invalid
selection. Undo restores document bytes; selection remains transient.

`session.setLock(_:isLocked:)` changes transient per-window interaction settings.
Both `edit` and batched set-node commands honor them after validating the input.
Undo/redo restores committed snapshots regardless of current locks. Creation,
deletion, archive bytes and history are unaffected by changing a lock.

Multi-node selection is transient and per window. Use sidebar Command/Shift selection, canvas Command-click, or Canvas → Select All Nodes (Command-Shift-A). Drag a selected node to move its editable group, or enter relative offsets in the group inspector. Group deletion removes incident edges; movement and deletion each take one undo step. Read-only nodes remain unchanged. See [selection verification](../../docs/selection-verification.md). Drag empty canvas to marquee-select visible node centers; Shift-drag adds to selection. The group inspector scales positions around the editable-node centroid and radii independently using positive factors. Identity scaling preserves original geometry exactly. Clipboard and other transforms remain pending. See [tools verification](../../docs/selection-tools-verification.md) for evidence and the unverified Shift-drag routing check.
