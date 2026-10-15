# Changelog

## Unreleased

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
