# Changelog

## Unreleased

- Toggle X, Y and Z editing locks with the matching keys while the canvas has keyboard focus.

- Lock or enable the hovered part from the canvas, using L or J when the canvas has keyboard focus.

- Preview authored linked cross-section outlines before choosing a profile.

- Print the authored rig templates as XML with the headless `-list-rigs` command.

- Offer canonical animation types for the document’s rig when creating a stored animation. Suggest an unused name based on the selected type until the name is edited.

- Support Qt’s `-toggle-color` launch option for newly opened document windows.

- Apply one Qt XML fragment at launch with `-paste-xml` in one Undo step per newly opened eligible document. With no `.ds3` input or output option, open one untitled document with default model colors. A read or validation error leaves that document blank and displays a diagnostic.

- Edit and reset the owning Model part’s width and thickness, and toggle unified deformation, from graph selection.

- Mirror the Model part that owns the current canvas selection while keeping its node and edge picks.

- Focus the active drawing profile from the canvas header to use its keyboard controls without clicking the drawing.

- Edit or restore Metallic, Roughness and Glow for the Model part that owns the current canvas selection.

- Change the role of the part that owns the current canvas selection while keeping its node and edge picks.

- Edit a Model part’s cross-section profile and rotation directly from its graph selection.

- Preview applied and retained component color images in the inspector without changing image assignments.

- Reset the Document Origin draft when replacing a document, even when both documents have the same origin.

- Reorder one component among its siblings from the component sidebar actions or row context menu, with one-step Undo.

- Browse a component group’s direct children and navigate back through its breadcrumb.

- Add new parts and paste components into the browsed group when placement is automatic.

- Assign selected edges to the chosen template bone from the Rig menu or with Command–Return.

- Select edges without moving or selecting nodes while preparing a bone assignment.

- Open a local .ds3 document by dropping it into the editor without replacing the current document.

- Edit subdivision, chamfer, and rounded ends from a graph selection with one owning part.

- Edit combine mode and smoothing for the components owning selected canvas nodes and edges while keeping graph picks in place.

- Edit or clear the Equipment Slot of the Model component that owns the current canvas selection.

- Set or clear a linked Model component’s Equipment Slot in the inspector, with Qt-compatible name storage and one-step Undo.

- Keep Escape with focused text fields, sheets, and animation controls while preserving canvas and geometry export cancellation.

- Rotate the canvas selection by a quarter turn around the other profile’s world axis while staying in the current profile.

- Show Front and Side together in an optional Side by Side workspace, with one editing pane and a read-only companion sharing the graph selection (#387).

- Add Command-Option-click and marquee subtraction for independent node/edge picks, preserving other selection and document history (#343).

- Add global Hide All Parts in Canvas and group visibility commands under Canvas > Part Visibility, preserving one-step Undo and mesh inputs (#343).

- Reveal a node or edge’s owning component from its context menu while preserving the current graph selection.

- Connect to the nearest existing node in Add mode when node hit areas overlap. A closer edge midpoint takes precedence when the pointer hits its tapered edge.

- Add captured graph-edit actions to canvas context menus and route secondary/Control clicks safely, cancelling Add mode before placement and clearing interrupted marquee presentation (#343).

- Keep a working component group as the destination for new parts while graph selection changes.

- Paste native or Qt clipboard nodes and Qt XML files into an explicitly chosen working group.

- Start a blank document by drawing a first node, composing a reference image, or opening an existing document from the canvas.

- Add undoable Hide Other Parts in Canvas and Show All controls for selected component subtrees and part owners, preserving mesh generation and unrelated flags (#343).

- Reveal selected generated joints by expanding their hierarchy ancestors, with window-owned disclosure and guarded scrolling (#367).

- Support Shift-drag panning in mesh previews while preserving orbit and bone-pick safety (#367).

- Keep profile controls visible in narrow editor windows and give Front and Side equal drawing space.

- Click a companion profile to make it the editing pane without placing or selecting a graph element.

- Press E with a graph selection and canvas focus, or choose Switch Editing Profile in the Canvas menu, to edit the selection in the opposite profile.

- Support trackpad pinch zoom and rotation-driven horizontal orbit in mesh previews, pausing automatic motion during gestures and invalidating obsolete picking input (#367).

- Expose experimental preview mode and generated-rest Model/Bones/Weights controls in the View menu with current-window and presentation guards (#367).

- Select generated bones directly in the experimental rest preview with guarded click-versus-drag input and cancellable background picking; retain displayed geometry and keyboard inspection if picking preparation fails (#367).

- Add independent Model, Bones and Weights controls to experimental generated-rest inspection, preserving the full camera frame, selected joint and numerical properties when geometry or weight colors are hidden (#367).

- Add a resizable Model/Generated Rest workspace with one per-window rest session, shared camera and stale-safe focused controls; preserve selection and camera across presentation changes (#367).

- Add a source-ordered generated-joint hierarchy and read-only parent, endpoint, length, radius and signed-angle inspection to the experimental rest preview; preserve copied rig data if hierarchy preparation fails (#367).

- Show the selected joint’s numerical weight range and influenced body-triangle count in the experimental rest preview, publishing these values with their matching mesh (#367).

- Add an isolated experimental generated-rest rig preview with grounded skeleton/body geometry, weight highlighting, all-joint selection, and guarded camera controls; keep the production core pin unchanged (#367).

- Add an isolated experimental native rig-template preview with complete solids/rings, exact-name selection, background preparation, stale-result protection and camera menu controls; preserve the production core pin (#144).

- Show rig assignment progress with stored/selectable counts, select unassigned or chosen-bone edges, and highlight matches on hover without changing document history (#363).

- Clear exact stored assignments for a template bone or its descendant chain across the document in one Undo step, including hidden and locked parts (#361).

- Browse the pinned rig template bone hierarchy and stored assignment counts, then assign the chosen exact name to selected edges in one Undo step (#359).

- View Front, Side, and interactive Orbit rig-template diagrams with the selected bone highlighted while assigning edges.

- Assign or clear exact stored bone names on selected edges in one atomic Undo step, with mixed-value drafts and captured-source protection shared by single-edge controls (#357).

- Select editable graph edges across parts by the selected edge’s exact stored bone assignment, with stale-action protection and no history change (#355).

- Resolve About attribution from installed app resources without requiring the original SwiftPM build directory, and report missing packaged attribution safely (#344).

- Allow opt-in owned source-bake mip copying through the existing pinned core, validating level counts and aggregate payload quotas; default loading remains base-only (#288).

- Keep node and edge inspector actions bound to their original document and selection, preserving atomic Undo and read-only endpoint selection (#352).

- Connect two selected endpoints from the inspector or Canvas menu, with explicit surviving part settings, stale-action protection and one Undo step (#349).

- Add shared Help commands for the native project, issue reporting and upstream Dust3D, with visible link-opening failures (#348).

- Include upstream contributor and supporter credits in both native About panels, available offline (#346).

- Use native About panels with bundled project MIT attribution and separate Help > Build Diagnostics commands in both apps, retaining the graph QA name (#344).

- Use the native adjustable inspector, standard Control–Command–I visibility command, compact section switcher and an accessible toolbar visibility toggle (#341).

- Announce completed geometry exports and warnings to assistive technologies, with one notification per export even for repeated destinations (#339).

- Match Qt reference-image pixel selection and alpha fitting while preserving 16-bit sample precision; retain correct RGB16 transparency decoding despite a Qt reader defect (#337).

- Package and verify the seven pinned rig templates for native SDK consumers and installed file-preview bundles (#195).

- Add searchable Keyboard Shortcuts help with native command focus restrictions (#333).
- Archive exactly the signed app tree without generated Finder metadata, retaining executable permissions and framework links (#329).

- Prepare lossless hollow-thickness history and an explicitly gated local-core inspector experiment; production geometry support remains unchanged (#96).

- Add opt-in automatic preview rotation that respects Reduce Motion and pauses while dragging or inactive (#326).

- Add window-local Model Colors and Wireframe controls to the View menu, preserving material transparency in neutral preview mode (#324).

- Add native menu actions for orbiting, panning, zooming and fitting the focused 3D preview without changing the document (#322).

- Show the exact authored values applied at the current replay property step.

- Replay document construction in a separate window with adjustable speed and a textured 3D preview.

- Open a paused replay step as a new editable document.

- Add canvas-scoped arrow nudges and bracket spacing, explicit precision controls, and focus-safe gesture teardown (#45).

- Mirror live node and origin movement in the companion profile during canvas edits (#388).

- Add shared Weights From editing across selected wrapping groups with common target eligibility, exact retained references and one atomic Undo.

- Add explicit multi-group wrapping and surface-finish edits with mixed values, captured selection protection and one atomic Undo.

- Retarget copied wrapping body bindings to the copied body, preserving external references and opaque wrapping metadata.

- Add wrapping surface finish authoring for coat patterns, RGB ink, belly shading and generated cloth wrinkles, with cancellable drafts and one-step Undo.

- Mark the common role of selected parts in the Part Role menu.

- Enter a target in the node inspector to bend a chain from the keyboard.

- Shift-drag a graph selection to rotate it or bend a single endpoint chain.

- Add graph auto-color from displayed reference pixels and default-color reset, with source-bound atomic Undo and stale-raster rejection (#45).

- Add canvas one-degree keyboard rotation and explicit angle controls, with automatic pivot/descendant selection, native lock protection and stale-input rejection (#45).

- Open the Part inspector when multiple component rows link directly to one shared part.

- Show, hide, lock, unlock, enable, or disable directly selected parts in one edit.

- Add batch component part roles with atomic stitching grouping, shared-group reveal and one-step Undo (#45).

- Apply or clear color across selected components with the native color picker and one-step Undo.

- Apply or clear explicit colors for components owning selected graph nodes and edges while keeping the graph picks.

- Drag component rows before or after siblings, into groups, or to the document root.

- Select all visible component rows with Command-A when the component sidebar has focus (#386).

- Place selected components before or after a sibling from the inspector, with one-step Undo.

- Move selected components to a new parent in one Undo step while preserving hierarchy order.

- Add explicit component subtree deletion with shared-instance preservation, captured contextual targets and one-step Undo.

- Ungroup multiple selected components in one undoable operation while preserving their children and order.

- Add atomic Combine Mode and Normal Smoothing edits for multiple selected components, with explicit mixed values and one-step Undo.


- Select component graphs in the canvas from the sidebar context menu or by double-clicking a leaf row.

- Select a whole part graph from its nodes, edges, or inspector and reveal the linked component in the sidebar. Reuse each rendered node’s validated owner for constant-time whole-part availability.

- Preview a new node and adjust its radius before placing it on the canvas in Add mode. Keep cancellation bound to its placement request, refit on selection exit, discard held presses across tool changes, and allow inward placement at document coordinate limits.

- Adjust selected node radii using canvas-focused keyboard input or the canvas wheel, with one-step Undo. Radius menu and inspector actions remain available independently of canvas focus.

- Highlight the hovered node or edge in both canvas profiles, with node hits taking precedence over edges.
- Preserve numeric move and scale controls for mixed and edge-only selections, expose additive node accessibility actions, and batch graph edge deletion into one validated XML mutation.

- Select nodes and edges together, with explicit graph editing modes and one-step batch midpoint insertion.

- Reduce eligible selected nodes and reconnect their neighbors in one Undo step while preserving graph order.

- Refresh selectable export-warning accessibility text when the result changes (#235).

- Add Insert Midpoint to the edge inspector and Canvas menu, with one-step Undo and preserved edge direction.

- Bind origin-move callbacks to their pointer gesture so cancelled drags cannot affect a later gesture; Escape prioritizes origin mode over a concurrent export (#45).

- Reject node-canvas drag commits when the document, selection, or interaction locks changed during the gesture, preserving newer edits and undo history (#245).

- Add original procedural FBX export beside OBJ in the editor’s Export menu, with shared source-bound atomic publication, preserved diagnostics and independent Capsule re-import verification (#286).

- Add catalog-backed stored animation creation, type changes, timing/dynamic/surface parameter drafts and explicit defaults, with source-bound atomic Undo/Redo and lossless Save (#283).

- Add original procedural OBJ export to the editor toolbar and File menu, with captured-revision publication, source protection, cancellation/drain feedback and preserved export warnings (#281).

- Add owned Swift base/UV worker-request packets backed by the existing core codec, with bounded input and preserved error receipts; worker execution remains separate (#277).

- Retain valid mesh previews across animation metadata Undo/Redo using history-owned geometry/material identities; reject obsolete auxiliary preview results (#275).

- Upgrade the pinned native core to reviewed revision `48b0ce2d`, including removal of automatic stitching debug SVG writes; feature quarantines remain in place (#272).

- Preserve the latest waiting preview independently for up to eight document scopes, with FIFO fairness and explicit backlog diagnostics (#271).

- Refresh native text Undo/Redo command availability after editing and undo-manager changes (#145).

- Clear removed animation selections when publishing edits and history transitions, independently of list reads (#145).

- Add a native stored-animation inspector with selection, source-bound rename/duplicate/delete, inline exact-text drafts and scoped graph shortcuts; playback remains unavailable (#145).

- Add stale-source animation edit targets and editor metadata workflows with latest-request list adoption, lifecycle retirement and geometry-independent history; native controls/evaluation remain pending (#145).

- Add actor-owned stored-animation selection, fresh-ID creation/duplication and source-correlated list presentation, isolating optional metadata errors from graph editing; native UI/playback remain pending (#145).

- Preserve exact animation bytes and redo for restored parameter transactions (#145).

- Add lossless stored-animation listing and create/rename/type/parameter/duplicate/delete commands with exact history and opaque-data preservation; native evaluation/playback remain quarantined (#145).

- Connect accepted editor snapshots to an injected export workflow with source revision receipts, history preservation and lifecycle cancellation; native encoder/menu binding remains unavailable by default (#146).

- Serialize final export source checks and atomic publication with accepted editor commands, preserving committed success on late task cancellation; native UI binding remains pending (#146).

- Add current-document export admission around background encoding, rejecting replaced documents and stale revisions without publishing output; app-level publication coordination remains pending (#146).

- Reject export targets hard-linked to a document opened through a symlink before encoding or publication (#146).

- Add an injectable document-snapshot export file service with source protection, atomic publication and retained diagnostics; native encoder/UI adoption remains pending (#146).

- Open multiple .ds3 documents at launch using positional paths or repeated --open-document flags.

- Add an explicit-fixture QA launcher using process-local AppKit restoration isolation while preserving normal launches and saved state (#257).

- Recheck actual recovery storage before each write so failed shrinking replacements cannot fund growth beyond the retained-byte budget (#248).

- Reject recovery capture after a failed replacement load, preserving its original error and the previous accepted document (#248).

- Prevent editor writes and Cut from using a retained preview after a replacement document fails to load.

- Require an exact PID and versioned notification channel for composition cancellation, ignoring older broadcast requests and bounding pending cancellation work (#56, #248).

- Add bounded app-owned recovery copies targeted to an exact process, with PID/UUID-correlated receipts, preserving original files and undo history (#248).

- Add native edge bone assignment with Apply, Clear, draft reset and lossless undo/redo; rigged preview remains unavailable (#247).

- Expose stored rig-template and eyelid parameters in the native inspector, preserving undo/redo and lossless save; skeleton generation and pose preview remain unavailable (#254).

- Add lossless, undoable stored rig-template and eyelid parameters with actor-prepared snapshots; skeleton generation and pose preview remain unavailable (#246).

- Route selectable node-ID copying through the native read-only field editor instead of copying a graph fragment (#235).

- Refresh the selectable node ID accessibility value when inspector selection changes while retaining copyability (#235).

- Move and resize existing reference-image crops with Draw/Adjust tools and eight visible handles; preserve numeric editing, bounded geometry and atomic composition Apply (#56).

- Bound editor preview work to one active operation and one latest waiting archive; retire queued cancellation promptly and keep cleanup serialized with explicit backlog errors (#243).

- Select mixed material preparation without imported-only image admission, and clear supported surface-detail notices only after a confirmed source-baked frame.

- Refuse to compile a core checkout that restores the quarantined GLB material catalog C API. The reviewed core pin is unchanged.

- Preserve positive subnormal MASK alpha through interpolation and factor multiplication on GPUs that flush subnormal arithmetic (#169, PR #171 review).
- Retain typed source-result mip chains and route them through shared viewport/file-preview rendering, preserving base-only defaults and material-failure fallback. Native accessor adoption remains pending.

- Add bounded explicit Metal mip uploads and trilinear sampling with conservative Float caps and minified-alpha routing; native/app mip adoption remains pending.

- Validate owned texture mip chains and cumulative copies; reject unavailable sampling levels in the base-only source-bake loader. Native mip and GPU adoption remain pending.

- Render mixed imported/procedural materials in macOS Quick Look and thumbnails, retaining ordinary geometry on optional material failure and reporting original causes.

- Render mixed imported/procedural materials in the editor through shared preparation, preserving exact document history, asset bytes, selection, camera and revision-safe geometry fallback.

- Render mixed imported/procedural materials in the standalone viewer through shared bounded preparation, retaining authored imported rendering for purely imported surfaces and geometry fallback on material failure.

- Preserve finite nonnegative imported alpha cutoffs through source baking and both Metal paths, including cutoffs above one and positive values below Float precision.

- Add an explicit editor document-launch argument for unattended native QA through the standard document controller, with bounded paths and original open-error reporting.

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

- Import, assign or clear a shared texture image for the Model components owning graph picks in one undo step.

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

- Set a Model part’s cross-section rotation to −90°, 0°, or +90° with one click and one undo step.

- Author reflected copies from the part inspector and initialize an absent canvas origin in the same Undo step.

- Add native width/thickness scale drafts and unified deformation controls with explicit unsupported-value replacement and offscreen inspector verification.

- Reset a Model part’s saved width or thickness scale to 1 independently, with one undo step.

- Add native part shape-modifier toggles and explicit unsupported-value replacement menus, with repeatable offscreen inspector QA in light/dark appearances.

- Restore legacy comma-decimal rotation and deformation metadata compatibility with byte-preserving semantic no-ops and strict numeric validation.

- Show the built-in cross-section outlines next to their names in the native preset picker.

- Add lossless part cut-face preset/profile and rotation commands, cycle-safe history and regenerated previews; native controls follow separately.

- Show how many part defaults and node overrides reference a Cut Face profile in the Part and linked Component inspectors.

- Add bounded, lossless part width/thickness and unified-deformation commands with exact undo/redo, preserved fine scales and regenerated previews; native controls follow separately.

- Author independent per-node width and thickness taper for editable Model nodes, with lossless saving and one-step Undo.

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

- Keep the current Add chain and radius when switching the editing profile in the Side by Side workspace.

- Add ordered component hierarchy inspection and lossless component-name commands to the document API, with atomic session history.

- Add File > Save All to save edited documents through the native document controller.

- Reject native save payloads while edits are applying or their document snapshot has been superseded, preserving the native File menu and providing retry guidance.

- Add a bounded composition recovery command that cancels only the newest unapplied draft when accessibility control is unavailable, preserving documents and in-flight Apply operations.

- Add a native Front/Side reference-image composer with crop previews, numeric and pointer crop selection, mirror/swap, cancellable drafts and one-step undoable image/origin Apply guarded against stale documents.

- Paste nodes from a Qt XML file into the focused document in one Undo step.

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

- Drop one or two image files into the reference controls to compose Front and Side images before applying them to the document.

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
