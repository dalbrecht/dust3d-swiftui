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

Transform Selected Nodes includes explicit Front X/Y and Side Z/Y local-center alignment on either or both axes. The mean uses editable selected nodes only; axis locks apply, other coordinates/radii remain unchanged and each action is one undo step. Empty/single/readonly/already-aligned selections preserve history. Global-origin alignment remains pending. See [verification](../../docs/local-alignment-verification.md).

Snapshots include the supported stored `origin`. Session `.apply([.setOrigin(position)])` validates before applying X/Y/Z locks; initializing an unavailable origin requires unlocked position axes. Global `SelectionTransform` cases (`usesOrigin == true`) align to the stored target and throw `unavailableOrigin` atomically when it is missing/unsupported. Zero/negative stored origins are valid explicit targets; no implicit Qt settlement occurs. Each origin edit/alignment is one undo step, independent of selection.

`CanvasBounds(nodes:referenceImageAspectRatio:origin:)` optionally fits a supported finite origin within ±1,000,000 together with visible node radii and the reference rectangle. Invalid origins are ignored; no document/history mutation occurs. Omit origin to retain the previous bounds behavior.

`OriginDrag(snapshot:projection:)` captures a supported origin, fixed projection and document/constraint epochs. `position(by:)` previews total screen-point translation without changing state. `session.commitOriginDrag(_:translation:)` rejects stale, invalid or oversized input atomically and commits one origin command; no-op gestures preserve history. `EditorSnapshot.documentIdentity` changes on Open, and `constraintRevision` invalidates gestures across lock cycles even when values return to their baseline. Each session/window owns its own identity.

```swift
let drag = try OriginDrag(snapshot: snapshot, projection: projection)
let preview = drag.position(by: CanvasPoint(x: 40, y: 20))
let committed = try await session.commitOriginDrag(drag, translation: CanvasPoint(x: 40, y: 20))
```

`OriginSettlement.center(of: [EditableNode])` validates all geometry and computes the radius-bound union center (zero for empty input), independent of part flags or selection. Invalid geometry throws `DocumentError.invalidNode`. `state.centerOriginOnModel()` and `session.centerOriginOnModel()` apply that target through the existing locked origin command/history, preserving no-op redo and exact undo bytes. Example: `let centered = try await session.centerOriginOnModel()`.

Session graph deletion now appends cleanup for affected owners still empty after the entire batch. Unrelated pre-existing empty/template parts stay intact, and remove-then-add batches retain their owner. Cut uses the same deletion path. Cleanup, profile repair and disconnected-part splitting share one undo transaction, with deleted selection pruned without revival. See [verification](../../docs/empty-part-cleanup-verification.md).

Rotate Around Selected Node provides four Front/Side quarter turns with exactly one editable pivot and a supported stored origin. The pivot stays fixed; traversal starts away from its neighbor nearest the origin in 3D. Axis/part locks apply, and each effective action is one lossless undo step. See [verification](../../docs/descendant-rotation-verification.md) for cycle/tie semantics and intentional Qt differences.

```swift
try await session.select(pivotID)
try await session.rotateDescendants(.frontClockwise)
```

`rotateDescendants(_:)` returns after applying the atomic transaction; it throws typed editor/document errors for invalid pivot selection, unavailable origin, read-only pivots or invalid geometry. Inspect `snapshot.canRotateDescendants` for UI availability.

Qt clipboard text uses bounded UTF-8 canvas XML. Native Copy offers richer native data first and a graph-only text fallback; plain text cannot transfer embedded asset bytes or distinguish selected nodes from profile dependencies. Paste validates and remaps the graph in one undo step. See [verification and pending native/Qt acceptance](../../docs/qt-clipboard-verification.md).

```swift
let snapshot = try await session.paste(snapshotXML: xmlData)
let copy = try await session.copyRepresentations(identifier: copyToken)
```

Text-paste errors are atomic; successful identical text advances per-window placement until Open. `copy.native` retains assets/selection metadata; `copy.snapshotXML` is the Qt text fallback.

Reference-image composition layout is pure and does not edit a document:

```swift
let size = try ReferencePixelSize(width: 1200, height: 800)
let crop = try ReferenceImageCrop(size: size, x: 100, y: 0, width: 600, height: 800)
let layout = try ReferenceCompositionLayout(front: crop, side: nil)
```

Pixel sizes/crops and projected output are bounded; invalid values throw `ReferenceCompositionError`. Layout returns placements and a proposed image-relative origin. It applies neither pixels nor origin to an archive. See [foundation verification](../../docs/reference-composition-foundation-verification.md); composition UI/commit orchestration remains #56.

Capture a composition target before asynchronous import/rendering, then commit prepared platform-validated PNG bytes through the session:

```swift
let target = ReferenceCompositionTarget(snapshot: snapshot)
let updated = try await session.applyReferenceComposition(
    png: png, origin: layout.origin, target: target)
```

Use `origin: nil` to retain the document origin. The atomic command throws `EditorError.staleReferenceComposition` if document identity/revision or constraint epoch changed. All PNG/origin validation completes before publication; no-ops preserve redo. `ReferenceCropProjection` maps preview points into bounded half-open crops without platform UI imports. See [verification](../../docs/reference-composition-workflow-verification.md).

`ComponentTree(document:)` caches immutable preorder rows, display-only fallback titles and depth, or the original hierarchy failure description without blocking graph editing. `visibleRows(collapsing:)` filters descendants in linear time. `EditorSession.selectComponent(_:)` selects a component exclusively and transiently; snapshots expose `selectedComponent` and `componentTree`. Publication prunes deleted component selection, and Undo does not revive it. Component-name edits use the existing atomic session apply/history path.

`ComponentTree.orderMoves(for:)` and `EditorSnapshot.availableComponentOrderMoves` derive non-no-op Up/Down/Top/Bottom availability from stored sibling order. Session `.apply([.reorderComponent(id:direction:)])` keeps selection and commits one history step; failed batches publish nothing and boundary moves retain redo. The controller regenerates after actual ordering changes because component combination can be order-dependent.

`try await session.groupComponents([firstID, secondID])` allocates a fresh component UUID on the actor, wraps those source-order siblings in one history step, and selects the new group atomically. Invalid/cyclic batches publish nothing. Use `.apply([.ungroupComponent(id:)])` or `.apply([.reparentComponent(id:parentID:)])` for the other structural commands; deleted group selection is pruned without Undo revival. These are document/session foundations for the upcoming native structural UI.

`selectComponents(_:)` atomically selects existing component IDs without dirtying the document. `selectedComponentIDs` is exclusive of graph/part selection; `selectedComponentID` and its inspector exist only for a singleton. Snapshot grouping/ungrouping eligibility is pure; document commands still validate every edit. Missing selections are pruned on publication and are not revived by Undo.

`ComponentTree.parentOptions(for:matching:)` provides ordered, cycle-safe presentation choices. Capture `ComponentReparentTarget(snapshot:)` for a singleton, then call `session.reparentComponent(to:target:)` with an explicit `ComponentParent.root` or `.component(id)`. Document epochs and selection are checked again on the actor; stale targets throw `EditorError.staleComponentMove` atomically.

`PartProfileOptions.candidates(in:excluding:matching:)` is a pure, source-ordered
projection for linked-profile choices. It excludes the owner and legacy IDs
that the engine cannot interpret as profile links, while matching title/ID
substrings case-insensitively. Duplicate names retain distinct exact identities.
Dependency cycles are still validated atomically when applying the command.

`PartCutFaceOptions.selections(current:)` supplies preset choices and the exact
current linked profile. It includes a nil, read-only source placeholder only for
unsupported metadata, so supported profiles never offer an inert unsupported
action. The UI disables that placeholder while keeping explicit replacements.

`hasEnabledGeometry` excludes disabled parts and CutFace-only profiles from
joined preview contributions. Profile nodes remain editable overlays and can be
used as linked cross-sections. Stitching inputs remain eligible for generation;
component configuration determines whether they produce a stitched surface.
Unsupported roles retain generation diagnostics instead of silently disappearing.

`MeshPreviewState.succeedEmpty(requestID:)` accepts an empty result only for the
active generation request, clears retained geometry/error state and advances the
preview revision. Obsolete, duplicate and cleared requests cannot erase current
output. Genuine failures still retain the last successful value as stale.
`EditorSnapshot.previewEmptyDescription` supplies distinct messages for an empty
graph, excluded contributors or a loaded document with successful empty output.

`ComponentWrappingPresentation` derives group-only active controls and ordered
field captions/ranges from immutable component metadata without framework imports
or side effects. None/unknown modes have no parameter fields; Skin has shared
geometry fields and Cloth has all seven. `ComponentWrappingField` provides stable
property identities for the SwiftUI inspector and is covered by pure tests.

`ComponentColorDraft` owns immutable transient hex text and native-conversion
issues. `editing(_:)` / `choosing(_:)` return replacement values without writing a
document; constructing from current source resets a draft. `canApply` blocks empty
or conversion-failed drafts, while nonempty invalid text reaches controller
validation. Native platform color conversion stays in the app. Unsupported source
summaries inspect bounded UTF-8 bytes and never change retained source data.


### Existing crop adjustment

`ReferenceCropProjection.interaction(at:crop:isAdjusting:)` chooses drawing,
moving or an edge/corner resize at pointer start. Retain that original displayed
crop and operation, then call `adjust(_:interaction:from:to:)` as the pointer moves.
Move preserves extent and clamps translation; resize preserves opposite edges,
retains the initial grab offset and enforces a one-pixel minimum. Inputs reject
nonfinite points and mismatched image dimensions. `handlePoint(_:crop:)` maps
visible handles back into preview points. Mirrored sources pass displayed crops
and convert the result through the existing composition draft.

```swift
let projection = try ReferenceCropProjection(size: imageSize, width: 400, height: 180)
let operation = try projection.interaction(at: start, crop: displayedCrop, isAdjusting: true)
let next = try projection.adjust(displayedCrop, interaction: operation, from: start, to: current)
```

The SwiftUI sheet defaults to Draw, switches to Adjust after a pointer selection,
and keeps numeric fields available for keyboard editing. Neither preview geometry
nor drag completion writes the document; composition Apply remains one transaction.

## Stored rig intent in snapshots

`EditorSnapshot.rigSettings` is immutable canvas intent decoded with the graph on
the editing actor. Accessing it does not parse XML, invoke an engine or imply rig
capability. Use `session.apply([.setRigType(.bird), .setHeadHasEyelids(true)])` for
one undoable batch. Snapshot intent follows open, accepted edits, undo, redo and
replacement; failed batches leave both intent and history untouched. Node selection,
locks and independent document sessions retain their normal semantics. UI and
native rig evaluation remain separate #144 work; this storage stage tracks #246.

`EditorExportTarget(snapshot:)` captures document identity and semantic revision.
`EditorSession.validateExport(_:)` rejects obsolete/foreign targets without
changing history; exact Undo does not revive an old target. This is admission,
not a publication lease. The app must coordinate final export publication with
editing and replacement (ADR 0101); no native export command is enabled here.

`EditorSession.publishExport(_:publication:)` checks identity/revision and runs a
trusted synchronous final commit without admitting intervening editor commands.
Encode before entering this background actor operation. Bind the file service's
publication coordinator to it; no await may split validation from the write.
ADR 0102 records the remaining native/UI/lifecycle and filesystem limits.

`EditorSession.animationSnapshot()` explicitly queries optional stored-animation
presentation off-main, returning matching editor identity/revision and original
metadata issues. `selectAnimation` is transient and independent of graph selection;
create/duplicate allocate fresh UUIDs atomically. Rows use byte-array identities
for Unicode-safe list selection. No native evaluation runs. ADR 0105 records
request/source correlation and remaining store/UI/runtime acceptance.

`AnimationEditTarget` binds metadata dialogs to exact source epochs and row IDs.
Actor `editAnimation` and targeted duplication reject replacement/Edit-Undo stale
sources before mutation, while preserving independent graph/clip selection and
original metadata errors. ADR 0106 describes the accepted-source store workflow.


`AnimationCreationTarget` captures the accepted document epoch before a creation
draft. Targeted `EditorSession.createAnimation(name:type:parameters:target:)`
validates that epoch before allocating an ID and applies the new record plus its
initial parameters as one transaction. Array `editAnimation(_:target:)` similarly
commits a parameter draft once, rolling back every edit if a later field fails.

`AnimationParameterDraft` is a pure exact-text transform over one known fixed type.
It validates changed fields only, preserves unsupported untouched values, restores
source spelling on exact numeric slider round trips and emits explicit override
removals for Default. `initialParameters(for:in:)` builds the displayed new-record
settings without generating frames. Type edits are separate drafts and preserve
unrelated parameters. These capabilities do not complete M6 evaluation/playback.
