# Dust3D editor model

Swift 6 library for one document’s selection, validated node edits and undo/redo.
`EditorState` is a value-based state machine; `EditorSession` serializes it away
from the UI actor and returns immutable snapshots. Each window owns a session.
`CanvasProjection` maps Front X/Y and Side Z/Y gestures to model coordinates.

Use `try await session.open(data:)`, select a node ID, then `edit(id:position:radius:)`.
Open/edit failures retain the previous state. One edit call is one undo step;
selection does not dirty the archive. Parts marked hidden, locked or disabled are read-only.
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

Multi-node selection is transient and per window. Use sidebar Command/Shift selection, canvas Command-click, or Canvas → Select All Nodes (Command-Shift-A). Drag a selected node to move its editable group, or enter relative offsets in the group inspector. Group deletion removes incident edges; movement and deletion each take one undo step. Read-only nodes remain unchanged. See [selection verification](../../docs/selection-verification.md). Drag empty canvas to marquee-select visible node centers; Shift-drag adds to selection. The group inspector scales positions around the editable-node centroid and radii independently using positive factors. Identity scaling preserves original geometry exactly. Native clipboard orchestration is described below; remaining transforms stay in the port plan. See [tools verification](../../docs/selection-tools-verification.md) for evidence and the unverified Shift-drag routing check.

Canvas and inspector transform menus provide Front/Side quarter turns, X/Y/Z flips, and X/Z exchange. Rotations/flips honor movement locks; the explicit X/Z exchange ignores axis locks, matching Qt, and retains part read-only protection. Reverse Selected Edges acts on edges with both endpoints selected/editable. The single-node inspector shows directed edge menus with Reverse/Disconnect actions. See [transform verification](../../docs/graph-transform-verification.md).

`EditorSession.apply` normalizes affected disconnected parts after graph removals, and `deleteSelection` uses that same path. The actor preflights the batch and injects UUIDs into explicit split commands, publishing one undo transaction. Direct document commands and `EditorState.deleteSelection` remain low-level building blocks without identity allocation; app callers use the session for complete removal behavior. See [splitting decision](../../docs/adr/0009-disconnected-part-splitting.md).

`EditorSnapshot.connectableNodes`, `connectionTargets`, `canAddNode` and `nextNodePosition` derive endpoint availability and outward extension without UI dependencies. App extension/connection uses `.joinNodes` inside the same actor transaction; failed batches preserve bytes, selection and history. Profile cycles and whole-chain constraints remain document-boundary validation. See [joining verification](../../docs/part-joining-verification.md).


Clipboard data stays off the UI actor. `copySelection(onlyEditable:)` returns a fragment without changing state; `copyPayload(identifier:onlyEditable:)` adds a caller-supplied Copy/Cut token. `paste(data:)` validates transport/archive data, allocates UUIDs, injects bounded construction partitions and commits one history transaction, selecting only explicit copied nodes. Profile-only dependency nodes are retained without becoming selected. Cut callers must write the payload successfully before `deleteSelection()`; the app's platform boundary enforces that order.

```swift
let token = UUID().uuidString // Allocate at the platform/session orchestration boundary.
let data = try await source.copyPayload(identifier: token)
let pasted = try await target.paste(data: data)
```

`NodeClipboardPayload` contains magic, a four-byte big-endian JSON length, version-1 metadata and raw `.ds3` bytes. Metadata is capped at 2 MiB, archive bytes at 256 MiB, Copy/Cut token at 128 UTF-8 bytes and selected IDs at 10,000; native graph/archive limits still apply. Malformed and unsupported payloads throw typed errors before publication. Failed pastes retain document, selection, undo/redo and placement bookkeeping. Repeated placement is per session/token and resets on Open. No system pasteboard, AppKit or SwiftUI type crosses into this module. See [decision](../../docs/adr/0012-native-clipboard.md) and [verification](../../docs/native-clipboard-verification.md).

`MeshPreviewState<Output>` tracks transient generated output independently of document history. Call `begin(requestID:)` with a fresh UUID for each generation, then `succeed(_:requestID:)` or `fail(_:requestID:)`. Obsolete completions are ignored. `isStale` identifies retained output during updates/failures. `clear()` invalidates pending work and removes retained output for empty/replaced/closed documents. No serialization or rendering framework is involved.

`selectEdge(_:)` selects one existing edge or clears selection, mutually exclusively with nodes. `selectedEdge` and `canEditSelectedEdge` expose inspection/mutation availability. Selection is transient and invalid IDs reject atomically. `session.deleteSelection()` deletes the editable selected edge through normalized splitting, or deletes editable selected nodes. Deleted edge selection is pruned and not revived by Undo. `CanvasProjection.edgeID(near:nodes:edges:tolerance:)` picks the nearest visible nondegenerate segment in screen points with document-order ties.

CanvasProjection now follows Qt's positive-Y-down scene coordinates. CanvasBounds optionally includes `referenceImageAspectRatio` to fit the image-height-normalized rectangle together with visible nodes. Front/side clockwise formulas follow screen direction in this convention. Model positions and saved bytes are not migrated by changing the projection.

`selectPart(_:)` selects an ordered part independently of nodes/edges, clearing those selections. Invalid IDs reject atomically; selection remains transient. Snapshots expose `parts`, `selectedPart` and `hasEnabledGeometry`; disabled parts hide editing overlays as well as excluding generation. Deleted/consumed part selections are pruned without being revived by Undo.
