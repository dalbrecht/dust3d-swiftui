# Changelog

## Unreleased

- Add atomic component grouping, ungrouping and cycle-safe reparenting document/session APIs, preserving subtrees, assets and exact undo/redo.

- Add undoable component sibling ordering (Up, Down, Top and Bottom), with boundary availability, lossless archive preservation and mesh regeneration.

- Add an ordered, collapsible component sidebar and name inspector with independent selection, linked-part inspection, undo/redo and lossless saving.

- Add ordered component hierarchy inspection and lossless component-name commands to the document API, with atomic session history.

- Reject native save payloads while edits are applying or their document snapshot has been superseded, preserving the native File menu and providing retry guidance.

- Add a bounded composition recovery command that cancels only the newest unapplied draft when accessibility control is unavailable, preserving documents and in-flight Apply operations.

- Add a native Front/Side reference-image composer with crop previews, numeric and pointer crop selection, mirror/swap, cancellable drafts and one-step undoable image/origin Apply guarded against stale documents.

- Accept bounded Qt snapshot XML on node Paste and publish a Qt text fallback alongside richer native clipboard data; native transfers retain embedded assets and selection metadata.

- Add explicit Front/Side descendant rotation around a selected fixed node, with origin-based parent selection, axis/part locks and lossless one-step undo/redo.

- Prevent delayed empty reference-image completions from resetting the camera or cancelling origin drafts; fit image removal and cached Undo correctly.

- Clean up parts emptied by graph deletion in the same undo step, preserving unrelated templates, nested content and assets and repairing deleted profile references.

- Add explicit model-bounds origin centering with axis locks, validated radius bounds and lossless one-step undo/redo.

- Add explicit Front/Side origin dragging with axis locks, cancellable previews, stale-document guards and one-step lossless undo/redo.

- Show an accessible, noninteractive origin marker in both canvas views and fit outlying origins without resetting the 3D camera.

- Add native document-origin coordinate controls and Front/Side alignment to the stored origin, with axis locks, unavailable-origin recovery, preview regeneration and lossless undo/redo.

- Add bounded, lossless document-origin reading/editing with exact undo/redo and preservation of unsupported existing origin fields.

- Align selected editable nodes to their local Front/Side center on either or both axes, respecting locks with one-step lossless undo/redo.

- Add native part selection, naming, visibility, locking and mesh-disable controls with lossless undo/redo and save support.

- Import/render bounded native reference images with undoable removal, per-window opacity/visibility and lossless existing asset handling; align the canvas and clockwise transforms with Qt’s positive-Y-down image coordinates.

- Add lossless, undoable Qt-compatible reference-image asset commands, bounded PNG bytes and asset-aware transaction change detection.

- Make inspector Reset replace invalid or empty formatter drafts even when the underlying numeric values have not changed.

- Add front/side edge picking, accessible edge sidebar selection, directed edge inspection, reversal and deletion with normalized splitting and undo/redo.

- Retain the last valid editor mesh during generation updates/failures, with explicit stale status, retry and obsolete-result protection.

- Add native node Cut/Copy/Paste and context-aware Select All, with versioned transport, fresh identities, normalized readonly/disconnected copies, one-step undo and lossless cross-window saves.

- Add document-level node clipboard fragments, explicit identity remapping, linked-profile/asset preservation and atomic paste undo.

- Join editable endpoints across parts with source settings, directed chain extension, cyclic-profile protection, lossless unrelated data and one-step undo/redo.

- Split disconnected parts after editor node/edge removal, preserving style and unknown metadata, hierarchy placement and one-step undo while keeping generated models previewable.

- Add lossless edge reversal, front/side quarter turns, axis flips and explicit X/Z exchange with one-step undo and direction-aware edge inspector actions.

- Add front/side marquee selection and lock-aware group position/radius scaling around the editable selection center, with atomic undo/redo.

- Add multi-node selection, group dragging and relative movement, and atomic group deletion with lock-aware undo/redo and lossless bulk archive commands.

- Add per-window X/Y/Z and radius interaction locks with canvas controls, inspector protection, lock-aware drag previews and Canvas menu keyboard commands.

- Add node/part creation, automatic chain extension, edge connection/disconnection and node deletion with incident-edge cleanup, grouped undo/redo and lossless saves.

- Add a separate SwiftUI editor with per-window documents, node selection and front/side movement, coordinate/radius editing, undo/redo, native open/save, and asynchronous mesh preview.
- Share the Metal renderer between viewer and editor; package and check Qt-free linkage for both apps.

- Add lossless editor archive storage, validated node commands, bounded undo/redo transactions, atomic file persistence, and measured coverage gates.

- Consume the Qt-free engine from a pinned external core revision and remove the duplicate Apple-side native adapter.

- Add a Qt-free C++17 engine library and C bridge, with validated `.ds3` archive loading.
- Add a native SwiftUI/Metal macOS viewer with file opening, orbit/zoom, wireframe, and camera fitting.
- Pin c65llc coding standards, assemble Codex instructions, and document native/C++ supplements and gaps.
- Add document-loading regression tests, native validation commands, and a local app bundle/run script.

Original Dust3D release history remains in `CHANGELOGS`.
