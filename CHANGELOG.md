# Changelog

## Unreleased

- Add an actor-owned generation-session SDK with bounded retained caches, copied indexed results, explicit cache diagnostics and reset, backed by the reviewed core session API; existing stateless app loading remains compatible.

- Render viewer and editor previews with unique vertices and UInt32 Metal index buffers, reject payloads beyond device buffer limits, and preserve expanded SDK compatibility, camera revisions, empty results and stale-failure behavior.

- Add copied, Sendable indexed mesh loading with explicit native payload budgets and preserved failure diagnostics, backed by the reviewed core indexed-buffer API.

- Add native group wrapping mode, keep-children, face-count and mode-specific geometry controls with explicit unsupported-value replacement, and adopt reviewed positive-area mesh export validation.

- Adopt the reviewed bounded-angle core fix for finite Cloth-opening and straight-profile previews, and connect lossless wrapping commands to the editor controller with validated drafts and exact history/save publication. Native controls follow separately.

- Add lossless group wrapping commands with mode-dependent defaults, bounded geometry parameters, exact undo/redo and a reviewed core numeric-validation pin. Native controls follow separately; low-density opening generation remains tracked in core issue #13.

- Clear successful empty mesh previews without retaining removed geometry, while preserving stale output and diagnostics for genuine generation failures.

- Add lossless isolated stitching-loop interior fill editing with native role-specific controls and exact undo/redo.

- Add lossless component stitching closures, segment counts and loop-cap parameters, native group controls, and configured line/loop geometry tests.

- Add lossless procedural part roles and native role controls; profile-only documents keep editable nodes with an intentionally empty mesh preview.

- Add native cut-face presets, searchable linked-profile selection and half-turn rotation drafts with preserved unsupported/unresolved source metadata.

- Add native width/thickness scale drafts and unified deformation controls with explicit unsupported-value replacement and offscreen inspector verification.

- Add native part shape-modifier toggles and explicit unsupported-value replacement menus, with repeatable offscreen inspector QA in light/dark appearances.

- Restore legacy comma-decimal rotation and deformation metadata compatibility with byte-preserving semantic no-ops and strict numeric validation.

- Add lossless part cut-face preset/profile and rotation commands, cycle-safe history and regenerated previews; native controls follow separately.

- Add bounded, lossless part width/thickness and unified-deformation commands with exact undo/redo, preserved fine scales and regenerated previews; native controls follow separately.

- Add typed, undoable part subdivision, chamfer, rounded ends, extra rings and hard-join commands with lossless saving and regenerated previews; native inspector controls follow separately.

- Update the pinned core to fix rounded crossing mesh generation and preserve thin solids near weld boundaries.

- Add validated component normal smoothing cutoff editing with Apply/Reset, regenerated normals, lossless saving and exact undo/redo.

- Add component Normal/Inversion/Uncombined editing with regenerated previews, legacy inversion handling, lossless save and exact undo/redo.

- Fit mesh previews to narrow viewports so separated parts remain visible after opening or fitting a model.

- Add searchable component parent selection with explicit root/group destinations, stale-draft protection, Cancel/Reset, lossless saving and exact undo/redo.

- Refresh rebuilt app bundle timestamps so macOS can recognize updated icons and metadata at the same path.

- Add distinct temporary Editor and Viewer app icons for launch and Dock identification.

- Add component multi-selection and native Group/Ungroup actions with lossless saving, exact undo/redo and mesh preview regeneration.

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
