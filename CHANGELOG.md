# Changelog

## Unreleased

- Preserve positive subnormal MASK alpha through interpolation and factor multiplication on GPUs that flush subnormal arithmetic (#169, PR #171 review).

- Preserve finite nonnegative imported alpha cutoffs through source baking and both Metal paths, including cutoffs above one and positive values below Float precision.

- Add source-baked materials to the shared Metal viewport, preserving packed source metadata, alpha modes, sidedness, seam-safe indexing and atlas sampling limits, with revision-safe uploads and geometry fallback.

- Prepare source-aware bakes from one unchanged archive snapshot, with shared imported/procedural image budgets, contextual codec failures and background cancellation.

- Add owned source-aware texture baking to the Swift SDK, with per-triangle material policy, bounded decoded inputs and output copies, cancellable background generation, and the core's atlas sampling LOD restriction.

- Render supported embedded GLB materials in macOS Quick Look and object thumbnails through the shared bounded imported renderer, preserving read-only archives and original failure diagnostics.

- Display supported embedded GLB materials in the editor with current-frame loading, revision-safe errors and lossless edit/history preservation.

- Render supported imported GLB materials in the standalone viewer with authored UV/sampler policy, linear color/factors, PBR scalars, alpha modes and double-sided handling; preserve geometry fallback and remaining editor/file-preview/atlas/export limits.

- Adopt owned imported surface UV/RGBA metadata with explicit RGB encoding, aligned geometry and independently bounded background Swift copies; texture rendering remains pending.

- Adopt reviewed core `4db1bb7` for embedded imported geometry, lifetime-safe material/image metadata copies, and bounded background PNG/JPEG decoding. Imported material rendering, UV/baking and textured export remain pending; archives and original assets survive native edits and undo.

- Add immutable executable build diagnostics to both apps and a repeatable editor QA packaging mode that reuses its existing identity, omits preview providers and refuses to overwrite a running target bundle.

- Make viewer and Quick Look material notices reflect current baked or fallback rendering, preserving legacy limitations and original source-interpretation errors without blocking valid geometry.

- Add native component image import, retained-image selection and clearing with background pixel validation, cancellation, material refresh, shared-asset preservation and exact undo/save.

- Add lossless component color-image assignment, removal and atomic PNG asset import commands with exact asset-aware history and shared bounded PNG envelope validation; native import controls remain pending.

- Bound cumulative XML namespace expansion across clipboard and asset/header transfers, rejecting excessive growth with a typed limit error and preserving normal namespace meanings, assets and exact history.

- Add editor-owned macOS Quick Look and Finder thumbnail providers that render existing `.ds3` objects without rewriting their archives, with bounded read-only loading and material fallback.

- Show baked color, normal, metallic, roughness and emission in both native app viewports, with background preparation, camera continuity, ordinary-geometry fallback, original diagnostics and material retry; editor changes and undo invalidate obsolete bakes, and viewer baking uses one exact file snapshot.

- Add an owned background-uploaded Metal material renderer with color, normal, metallic, roughness and emission maps, linear alpha blending, depth handling and camera-sorted transparency. Production-encoder GPU tests cover pinned-core output; app viewport adoption remains pending.

- Prepare bounded, seam-aware indexed baked geometry for subsequent shared Metal adoption, retaining UVs, tangent frames, mapping states and component metadata; existing app previews remain unchanged.

- Add bounded retained-PNG decoding and a shared background archive-to-bake service, preserving straight alpha, source scanline order, original assets and per-asset errors; existing previews remain unchanged.

- Add copied Swift baked textures, expanded seam-preserving geometry, triangle tangents and a background baking actor with lifetime-safe native cancellation, using exact reviewed core revision `2703a17`; archive decoding and renderer adoption remain separate.

- Add opt-in copied Swift UV atlas metadata with explicit missing/ambiguous source states, bounded image dimension inputs and an exact reviewed core pin; the default app previews remain untextured.

- Add explicit component color drafts with native color selection, alpha-first hex support, actual RGB preview updates, preserved unsupported metadata and exact undo/save; alpha is saved while previews remain opaque.

- Add lossless Metallic, Roughness and Glow editing for Model parts, with bounded drafts, exact undo/redo and preserved unsupported metadata; current previews do not yet display these effects.

- Pair editor preview geometry with current source hints, discard obsolete metadata, and fall back to ordinary previews with a preserved diagnostic when optional source details fail.

- Add optional copied, Sendable mesh source hints through cached generation, preserving complete weights, opaque identities, explicit unknown/ambiguous kinds and independent payload budgets with strict boundary validation.

- Reuse bounded document-scoped core caches for editor previews, isolate replacement/stop cleanup, preserve stale and successful-empty behavior, and display cache-only diagnostics without blocking edits or save.

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
