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

Click an edge between node handles in Front or Side view to select it; selected edges use the accent color. The Edges sidebar offers the same selection using native buttons, including edges collapsed in a projection. The edge inspector shows direction and endpoints, can select both endpoint nodes, and exposes Reverse Edge and Delete Edge. Canvas menu commands also reverse/delete a selected edge; Delete is available for an editable edge. Node/marquee/Select All selection clears edge selection. Read-only/hidden endpoints are inspectable but cannot be changed. Deletion retains nodes and splits disconnected parts in one undo step.

Inspector Reset discards the native formatter’s text buffer as well as resetting numeric drafts. Blank/invalid text therefore returns to the selected node’s stored values without dirtying the document or creating undo history.

The SwiftPM `Dust3DEditorTests` target hosts native views in an offscreen AppKit window. It runs with `make ci` or `./script/swift.sh test --filter InspectorResetTests` on a macOS WindowServer session. The numeric Reset regression edits real native field text and invokes the shared Reset action, checking displayed output and document/history independence. No external UI automation permission is required.

Use **Reference Image → Import Reference Image…** for PNG/JPEG/BMP/GIF/TIFF. ImageIO reads/converts off the UI actor and applies orientation; animated/multipage inputs use their first frame. Inputs and encoded PNG output are limited to 32 MiB, dimensions to 8192 per side and pixel count to 16,777,216. Import and Remove are undoable; Show and Opacity affect only this window. Existing canvas.png bytes are decoded for display without rewriting them, and malformed/oversized assets show an error while remaining saveable/removable.

The canvas now uses Qt's image-height-normalized, positive-Y-down coordinates, with the complete reference at X/Z 0…width/height and Y 0…1. Fit includes visible nodes and the image; front/side clockwise transforms follow screen direction. This corrects the prototype's earlier Y-up canvas without changing stored coordinates. Import a precomposed turnaround image; the native composer adds independent Front/Side cropping and composition; final workflow acceptance is recorded below. Origin tools have separate verification records. See [the decision](../../docs/adr/0016-native-reference-images.md).

The Parts sidebar includes hidden, locked, disabled and empty parts. Select one to rename its legacy part name, toggle canvas visibility, lock geometry edits, disable its mesh contribution or select its nodes. Component names stay independent. Metadata changes are undoable; selection is transient. Controls remain available to restore inactive parts. See [native verification](../../docs/part-controls-verification.md).

Transform Selected Nodes includes explicit Front X/Y and Side Z/Y local-center alignment on either or both axes. The mean uses editable selected nodes only; axis locks apply, other coordinates/radii remain unchanged and each action is one undo step. Empty/single/readonly/already-aligned selections preserve history. Global-origin alignment remains pending. See [verification](../../docs/local-alignment-verification.md).

Expand Document Origin in the inspector to edit X/Y/Z, Apply Origin or Reset Draft. Position locks apply; missing/unsupported values need an explicit complete origin with unlocked position axes. Origin edits regenerate mesh placement while retaining document nodes. Transform Selected Nodes also offers six Front/Side alignments to that stored origin, disabled when unavailable. Zero is valid and no automatic settlement occurs. See [verification](../../docs/native-origin-verification.md); marker/dragging tools remain pending.

A noninteractive Origin scope marks the supported stored coordinates in Front/Side; it does not intercept node picking. Fit includes the origin, visible nodes and reference image. Origin edits/Undo/Redo recompute canvas bounds while preserving the mesh camera; explicit Fit retains its camera reset. See [verification](../../docs/origin-marker-verification.md).

Enable Move Origin in the canvas or Canvas menu, then drag the scope marker in Front or Side. Axis locks apply; radius/part locks do not. Release commits one undo step and exits the mode. Escape cancels without saving. Node picking remains available with mode off. Plane/viewport changes, Fit, other operations, replacement and close cancel drafts. Numeric Document Origin fields remain the keyboard alternative. See [verification and remaining pointer QA](../../docs/origin-dragging-verification.md).

Document Origin and the Canvas menu provide **Center Origin on Model**. It centers every node's radius bounds, including hidden/locked/disabled parts, independently of selection or reference image; empty models target zero. Axis locks apply and unavailable origins require unlocked axes. One centering operation is one undo step; opening/saving never implicitly settles the origin. See [verification](../../docs/origin-settlement-verification.md).

Deleting the last node of a part now removes its empty owner in the same undo step. Unrelated empty/template parts and all embedded assets remain preserved; linked cut-face profiles fall back to inherited/default shapes when their owner is deleted. Nested/unknown component content is retained. The final geometry deletion clears the preview without a generation error. Undo restores the complete original archive. See [verification](../../docs/empty-part-cleanup-verification.md).

Reference-image cache completions do not refit an absent image or cancel a new origin draft. Actual removal fits immediately, and restored cached images fit when they reappear. Loading UI is shown only for a real asset. Development tests inject `ReferenceImageServing` to control completion ordering without changing the production actor/codec; see [race verification](../../docs/reference-image-completion-verification.md).

Rotate Around Selected Node provides four Front/Side quarter turns with exactly one editable pivot and a supported stored origin. The pivot stays fixed; traversal starts away from its neighbor nearest the origin in 3D. Axis/part locks apply, and each effective action is one lossless undo step. See [verification](../../docs/descendant-rotation-verification.md) for cycle/tie semantics and intentional Qt differences.

Qt clipboard text uses bounded UTF-8 canvas XML. Native Copy offers richer native data first and a graph-only text fallback; plain text cannot transfer embedded asset bytes or distinguish selected nodes from profile dependencies. Paste validates and remaps the graph in one undo step. See [verification and pending native/Qt acceptance](../../docs/qt-clipboard-verification.md).

The reference composition raster foundation crops orientation-normalized images, centers Front/Side profiles on a white 512-pixel-high canvas, and encodes bounded PNG off the UI thread. The editing workflow below adds transient sources/crops and atomic Apply/Cancel; broader parity acceptance remains #56. See [foundation verification](../../docs/reference-composition-foundation-verification.md).

Choose Reference Image → Compose Reference Image to import Front/Side sources, edit X/Y/Width/Height in pixels or drag a new crop rectangle, mirror Side, swap profiles and inspect the white turnaround preview. Use Full Image resets the crop, including invalid field drafts. Original source pixels remain transient. Use Existing Image as Front treats the stored flattened canvas as one source.

Cancel discards drafts. Apply replaces canvas.png, optionally sets the image-relative origin with axis locks, and creates one undo step. The composer rejects a document or lock change made since opening; reopen it rather than overwriting newer state. Invalid input, active crop gestures and pending previews disable Apply. See [workflow verification and remaining native acceptance](../../docs/reference-composition-workflow-verification.md).


If a composition sheet cannot be controlled through accessibility, run its installed bundle executable with `--cancel-reference-composition`, for example:

```sh
/path/to/Dust3DEditor.app/Contents/MacOS/Dust3DEditor --cancel-reference-composition
```

This requests cancellation of only the most recently opened composition draft in running instances with that bundle identity and login session. It does not launch an editor window, save, close documents or accept file paths. It refuses to cancel during Apply and never falls back to an older sheet. The request uses a local distributed notification; shell sandbox restrictions can block delivery, and the printed request message is not an acknowledgement. Verify that the sheet closed before continuing. Run the executable inside the same app bundle as the target editor; the plain SwiftPM binary lacks a bundle identity.
