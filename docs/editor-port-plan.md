# Native editor implementation and repository plan

Status: October 16, 2026. The viewer, pinned-core migration (#3), and lossless document/undo foundations (#5) have landed. A separate editor now implements selection, front/side movement, coordinate/radius edits, per-window undo/redo, and native open/save; see [implementation and validation](editor-app-verification.md). Graph topology editing landed in #9 after automated review and CI. Per-window X/Y/Z and radius interaction locks now form the next tested stage; these constrain new edits without entering archive or undo data. Full feature parity below remains pending. Estimates below are sequencing guidance, not a delivery commitment. Multi-node selection, group movement and deletion now have an implementation and [verification record](selection-verification.md); [Marquee and group scaling](selection-tools-verification.md) are implemented, with additive modifier routing still requiring a manual pass. [Basic quarter turns, flips, X/Z exchange and edge reversal](graph-transform-verification.md) are implemented. [Disconnected part splitting after graph removal](part-splitting-verification.md) is implemented with metadata preservation and engine integration tests. [Cross-part endpoint joining and outward chain extension](part-joining-verification.md) are implemented, with source-settings replacement, atomic profile-cycle rejection and engine integration. [Document clipboard foundations](clipboard-foundation-verification.md) now support selected-node fragments, profile dependencies, asset merging and explicit identity remapping; [Native clipboard commands and session normalization](native-clipboard-verification.md) now implement cross-window Cut/Copy/Paste, readonly construction, fresh identities and exact undo/save preservation; Qt snapshot-text adapters are implemented with [automated verification and pending native/Qt acceptance](qt-clipboard-verification.md). Edge selection and bounded reference images are implemented. Native part naming/visibility/lock/disable controls have a [verification record](part-controls-verification.md). Local Front/Side alignment has a [verification record](local-alignment-verification.md). Lossless origin archive commands have a [verification record](document-origin-verification.md). Native origin coordinate controls and global-origin alignment have a [verification record](native-origin-verification.md). Origin markers and shared fitting have a [verification record](origin-marker-verification.md). Explicit origin dragging/cancellation is implemented with [verification and remaining physical pointer QA](origin-dragging-verification.md). Explicit model-bounds origin centering has a [verification record](origin-settlement-verification.md). Transaction-scoped empty-part cleanup has a [verification record](empty-part-cleanup-verification.md). Explicit descendant-pivot rotation is implemented with a [verification record](descendant-rotation-verification.md); implicit Qt settlement is deliberately replaced by explicit native actions (ADR 0023).

Editor previews now pair current geometry with optional source hints and preserve ordinary geometry when optional details fail; see [verification and limits](editor-preview-source-verification.md). Material/rig use and full M3 acceptance remain pending.

## Product boundary

Keep `Dust3DViewer` as a separate read-only macOS app with its own executable, bundle identifier, launch/package command, and release artifacts. Add `Dust3DEditor` as a different app, initially macOS 14+, Swift 6, SwiftUI and Metal. Share document/engine services and reusable rendering code; never make opening a model in the viewer start an editor session. Preserve the Qt app as a compatibility oracle during the port. iOS, cloud collaboration, and new modeling features are outside parity scope.

Full implementation means native support for the existing repository's document, modeling, material, rigging, animation, sound and export workflows. Feature names alone are insufficient: establish a fixture and acceptance case for each behavior before calling it complete. The current viewer supports procedural mesh previews only and is not an editable document model.

## Repository structure and ownership

**Selected end state: two public MIT repositories.** Keep [`dalbrecht/dust3d-swiftui`](https://github.com/dalbrecht/dust3d-swiftui) for Apple apps, and use [`dalbrecht/dust3d-core`](https://github.com/dalbrecht/dust3d-core) for portable C++ and its native C API. The user authorized repository setup on October 14, 2026. The core preserves the existing Git history and tracks [`huxingyi/dust3d`](https://github.com/huxingyi/dust3d); it is a maintained downstream, not a decision to stop integrating upstream. The Apple repository remains the existing GitHub fork and can be used to submit focused upstream contributions. The new core repository is a history-preserving duplicate with an explicit upstream remote and tracking branch, rather than a second GitHub-network fork. Preserve the original MIT copyright/license and all third-party notices; new project code uses MIT. Third-party components retain their existing licenses, not an assumed MIT relicensing.

| Repository | Owns | Must not own |
| --- | --- | --- |
| Apple apps (`dust3d-swiftui`) | Swift document/application layers, viewer and editor executables, SwiftUI components, Metal renderer/shaders, Apple packaging, UI tests | Geometry algorithms, duplicate vendored C++ dependencies, Qt controllers |
| Core downstream (`dust3d-core`) | `dust3d/`, required geometry dependencies, validated archive/document adapters, versioned C ABI, headless build/CLI, C++ tests/fuzzers and upstream integration | SwiftUI/AppKit, app state, Metal UI, Qt-dependent public headers |

Both repositories are established and the Apple apps consume an exact core revision. The core is the single source of truth for the native adapter. Cross-repository changes use paired PRs and exact commit pins, never unrecorded copies. Organize native code along these boundaries before moving it:

```text
Sources/Dust3DKit/                 # typed Swift engine/document adapter
Sources/Dust3DDocument/            # lossless archives, commands and history
Sources/Dust3DEditorModel/         # per-document state, actor session, projection
Sources/Dust3DApplication/         # future cross-app workflow extraction if needed
Sources/Dust3DRendering/           # shared Metal rendering and picking
Sources/Dust3DViewer/              # standalone read-only app
Sources/Dust3DEditor/              # document scenes, tools, inspectors
Tests/<matching target>/          # behavioral tests
Tests/Compatibility/              # licensed archive and parity corpus
docs/adr/                        # architecture and compatibility decisions
```

These are target boundaries, not instructions to add empty modules. Extract rendering when the editor first needs it; add other targets when they gain real responsibilities. Keep `Package.swift` as the authoritative dependency/build declaration. Separate app packaging scripts and bundle identities. Put legacy Qt code under a documented reference boundary; avoid moving inherited trees merely for cosmetic consistency.

### Split tradeoffs and migration gates

Two repos improve upstream merges, portable CI and release ownership, but introduce coordinated versioning, cross-repo changes and binary supply-chain work. A single repo is simpler while editable snapshot and asset APIs are changing. Do not copy the engine into a second repo and independently patch both.

1. Finish viewer landing and establish editor load/save requirements (M0–M1). Setup verified both the Apple fork master and upstream HEAD at `3fbcaa7a3e8792d1c2ca31ca2ade442dcd21b222`; preserve that provenance and re-audit divergence on each synchronization. The core starts from that ancestry plus the native adapter, with no rewrite of inherited history.
2. Give the engine a standalone CMake build and headless contract tests in addition to its current SwiftPM build. Use explicit source/dependency lists. Demonstrate a clean build with no Apple or Qt frameworks.
3. Version the C API: capability query, ABI version, sized structs, explicit ownership/destruction, error/status contracts, and document/mesh/asset handles. Keep STL, Qt types and exceptions private. Capture limits and cancellation semantics in public documentation.
4. Maintain the history-preserving core repository and all dependency license notices. Keep upstream geometry changes separate from native-adapter changes where possible. Resolve inherited warning fixes through focused C++ PRs rather than whole-tree formatting.
5. Source integration now uses the core SwiftPM product at an exact committed revision, with Package.resolved checked in. SwiftPM cannot assume a C/C++ target can import source files from outside its package; prove the layout on a clean clone, or build/link the standalone core through a generated local artifact. Do not use a moving branch or developer-specific search path.
6. When the ABI stabilizes, publish checksummed static XCFramework releases for arm64 and x86_64 macOS with headers/module map, symbols and licenses. Consume a versioned SwiftPM binary target from the Apple repo. Support a documented local-source override for engine development. Test deployment-target and Swift toolchain compatibility, and package transitive C++ dependencies without symbol duplication.
7. Run contract fixtures against every candidate core release, then update the Apple dependency in its own PR. Upgrade viewer and editor together only after both pass. Retain the last compatible engine release for rollback.

Each repo gets its own pinned coding-standards configuration. The core inherits the existing C++17 `.clang-format`, `.cc`/`.h` conventions and project C++ supplement. The Apple repo inherits Swift 6/concurrency and UI standards. The existing standards audit identifies missing upstream C++ rules and native-boundary guidance; propose those upstream separately. CI must measure new Swift domain coverage and instrument new C++ adapter code explicitly; the current Swift coverage does not measure the inherited engine. Document justified legacy/manual exceptions instead of advertising a false whole-engine coverage gate.

## Architecture

Use value-based editable document state with stable UUIDs, ordered component hierarchy, node/edge graph, materials, reference images, imported assets, rig definitions, animations and sound parameters. Preserve unknown attributes and archive items so unsupported future fields survive save. Separate semantic document state from selection, camera, window layout and generation caches.

Commands validate invariants and produce the next state plus an undo record. A drag is one undo transaction, not one record per pointer event. The main actor owns scene presentation and command routing; actors own file access and generation scheduling. Never place geometry generation, texture baking or export on the main actor. Every derived result carries its source revision, and stale results cannot replace newer state or be exported as current.

Extend the engine with narrow capabilities: decode/encode document, generate indexed geometry with source IDs and UVs, generate textures, import/export assets, generate rigs and evaluate animations. Swift owns app workflows; portable algorithms stay C++. Investigate Qt-dependent services individually rather than translating `QObject`/signals into the engine. Retain serialized native entry points until globals and UUID generation are audited. Add cooperative cancellation only at safe algorithm boundaries; evaluate a worker process for hard time/memory limits and crash containment before general distribution.

## Existing feature inventory and parity acceptance

Source anchors are repository-relative references for implementation planning. `application/sources/document.h` and the `document_{node,edge,part,component}.cc` files define editing semantics; `document_window.cc` defines file/menu/export workflows. Core algorithms remain under `dust3d/`.

| Area | Required native behavior | Acceptance evidence |
| --- | --- | --- |
| Documents | New/open/save/save as, dirty state, reopen, multi-window, recent files, atomic saves, autosave/recovery, duplicate and asset retention | Qt→native→Qt fixtures; failure cannot corrupt original; cancel/close recovery cases |
| Graph editing | Add/connect/delete nodes and edges, reverse edges, move/scale/radius, selection, copy/cut/paste, undo/redo, front/side profile and reference turnaround images | Command invariant tests; continuous gesture undo; keyboard and pointer workflows |
| Constraints | X/Y/Z/radius locks; part visibility/lock/disable; origin handling and mirror behavior | Locked entities unchanged; mirrored results match fixtures |
| Parts/components | Naming, ordered hierarchy, grouping/reordering, selection previews, combine modes, targets, segment counts and smoothing cutoff | Hierarchy round trips; engine parity on unions/differences and ordered combinations |
| Modeling modifiers | Subdivision, interpolation, hard joins, rounding/chamfer, width/thickness/unified deformation, cut faces/rotation/linked profiles, hollow thickness, loop fill, close side/front/back including depth/sharpness, wrapping | One focused fixture per modifier plus interacting combinations; tolerance-based geometry comparisons |
| Materials/textures | Component colors/images, transparency, metalness, roughness, emissive, countershade, procedural detail, UV generation and baked normal/AO/material maps | UV/index integrity; linear/sRGB correctness; deterministic bake comparisons and reference renders |
| Imports | Existing embedded GLB assets and their transforms/materials; reference image formats actually supported by Qt | Asset preserved on save; malformed/unsupported inputs fail explicitly; no partial model presented as complete |
| Rigging | Existing rig types, eyelid option, bone hierarchy/properties, weights, skeleton display and IK manipulation | Joint/weight invariants, rest-pose parity, known deformation fixtures |
| Animation/audio | Animation list/name/type/parameters, generation, preview, timeline/playback and existing procedural sound/WAV workflows | Stable duration/time units; pose fixtures; audio length/format; cancellation and export diagnostics |
| Export | OBJ, GLB, FBX, GLB/FBX with WAVs; static and rigged/animated paths; headless/batch behavior | Re-import into independent consumers; topology, UV/material, skeleton and animation assertions; failed writes leave no claimed success |
| Desktop experience | Menus/shortcuts, tools and inspectors, progress/errors, drag/drop, camera modes, wireframe, fit, focus/accessibility, settings | Native UI scenarios, keyboard-only operation, VoiceOver, large-document interaction checks |

Do not assume every available core algorithm is exposed by the current Qt app. During M0 enumerate actual menu actions, serialization fields and animation/sound types into a tracked parity checklist. Include command-line/agent modeling tools as file producers; preserve their existing `.ds3` interoperability.

## Delivery milestones and PR sequence

Each milestone produces independently reviewable PRs and keeps the viewer usable. Start with a compatibility corpus before broad UI construction. No milestone is complete solely because its screens exist.

### M0 — Viewer landing and parity baseline

- Land the standalone viewer PR; preserve its product identity and documented procedural-preview limits.
- Inventory Qt actions and serialized attributes, mark each supported/preserved/rejected, and create issues for the following milestones. Record feature changes already present in this fork versus upstream Dust3D.
- Build fixtures for modifiers, textures, embedded imports, rigs, animations/audio, malformed archives and real user documents with permission. Capture Qt numerical/export output and reference renders; avoid byte-exact mesh comparisons when ordering is incidental.
- Done: agreed parity matrix and fixtures; viewer CI passes; first editor scope is graph editing and lossless save, without unsupported feature loss.

### M1 — Editable document and safe persistence

Dependencies: M0. Suggested PRs: document schema/codec; commands/invariants; persistence/recovery.

- Add a decode API that returns editable data and retained archive assets, rather than only generated vertices. Add an encoder with validated offsets and checked size arithmetic; audit the inherited writer's deprecated formatting and error handling.
- Model stable IDs, hierarchy order, unknown fields and assets. Define migration/version policy. Preserve features before their editing UI exists; prohibit a destructive save if preservation is impossible.
- Introduce pure add/remove/move/radius/connect commands, undo transactions and typed errors. Wrap atomic writes, file coordination and recovery in a thin file service.
- Done: document→save→reopen semantic equivalence; Qt loads native-saved fixtures; unknown assets preserved; invalid commands leave state unchanged; disk-full/interrupted-write/close-cancel cases tested.

### M2 — Separate editor app and interactive canvas

Dependencies: M1. Suggested PRs: editor scene/shared rendering; selection/picking; graph tools/undo UI.

- Add the editor executable and separate bundle ID; extract shared renderer without moving viewer state into editor modules. Use document scenes with independent state/undo per window.
- Add front/side orthographic editing, 3D preview, reference image placement, node/edge overlays, hit testing, marquee/multiselect and coordinate transforms. Edge picking/inspection is implemented; see [verification](edge-selection-verification.md).
- Implement drawing/connection, selection, move/scale/radius, delete, clipboard with UUID remapping, constraints and keyboard commands. Debounce preview generation, retain last valid mesh with explicit stale/error state (implemented; see [verification](preview-resilience-verification.md)).
- Done: create a capsule and multi-part sword, edit both, undo/redo, save/reopen in Qt; two windows do not share selections or undo; gestures remain responsive while generating.

Reference-image archive commands and asset-aware undo are implemented; [foundation verification](reference-image-foundation-verification.md) records preservation and bounds. Platform import/decoding, image-height coordinate alignment and rendered reference images are implemented; see [native verification](reference-image-ui-verification.md). Cropping/composition, origin tools and the broader M2 acceptance checks remain.

### M3 — Complete procedural modeling

Dependencies: M2. Suggested PRs grouped by component hierarchy, modifier families and generation scheduling.

Native flat part selection, legacy naming, visibility, locking and disabling are implemented; see [verification](part-controls-verification.md). The document layer now exposes ordered component parent/child identities and lossless component-name commands ([ADR 0031](adr/0031-component-hierarchy-foundation.md), #62). A collapsible native tree, exclusive component selection and name inspector are implemented ([ADR 0032](adr/0032-native-component-tree-selection.md)); [native rename/history/rendered checks pass with remaining keyboard/VoiceOver limits](component-tree-verification.md). Sibling ordering now has document/session/controller tests and an inspector menu ([ADR 0033](adr/0033-component-sibling-order.md)); [native menu/order/save/history checks pass, with modifier differential acceptance pending](component-order-verification.md). Grouping, ungrouping and cycle-safe reparenting now have document/session foundations and [pinned-engine union/history verification](component-structure-foundation-verification.md) ([ADR 0034](adr/0034-component-structure-foundation.md)); native multi-selection and Group/Ungroup controls now have [rendered and native save/history verification](component-grouping-verification.md) ([ADR 0035](adr/0035-native-component-grouping.md)); searchable parent controls and stale-target protection now have document/session/controller coverage and [native save/history and accessibility-text evidence](component-reparent-verification.md) ([ADR 0036](adr/0036-native-component-reparenting.md)); modifier differential acceptance remains pending. Subdivision, chamfer, rounded ends, interpolation and hard-join document/controller foundations have automated tests; native controls now have offscreen rendered light/dark and unsupported-source verification ([native controls](native-part-modifiers-verification.md), ADR 0043), with native interaction acceptance still pending ([verification and pending native acceptance](part-shape-modifiers-verification.md), ADR 0040). The rounded-crossing geometry regression prompted a reviewed core fix and exact-pin update. Width/thickness and unified-deformation document/controller foundations now have bounded lossless commands and real-core geometry/history tests ([verification](part-deformation-verification.md), ADR 0041); their native controls now have offscreen light/dark verification ([native deformation controls](native-part-deformation-verification.md)); pointer/keyboard and native history acceptance remain pending. Part cut-face presets, exact-ID linked profiles and normalized rotation now have cycle-safe lossless document/controller foundations with actual-engine geometry/history tests ([verification](part-cut-face-verification.md), ADR 0042); native preset, searchable linked-profile and rotation controls now have [offscreen verification](native-part-cut-face-verification.md), while native interaction and broader profile acceptance remain pending. Procedural Model/CutFace/StitchingLine/StitchingLoop roles now have lossless commands and native controls with [profile-only preview and offscreen verification](part-target-roles-verification.md), ADR 0045. Component stitching closures, segment counts and loop-cap parameters now have lossless commands, native group controls and [configured core geometry/history verification](component-stitching-verification.md), ADR 0046. Isolated loop-interior fill now has lossless commands, role-specific controls and [configured core/history verification](part-loop-interior-verification.md), ADR 0047; successful empty generation clears the preview through the reviewed core result and request-safe completion (ADR 0048). Native stitching interaction, other modifier families and broader differential acceptance remain pending. Hollow thickness is preserved legacy metadata without a current core generator consumer; its implementation remains open in #96 and is not counted as working geometry.

October 18 exploratory native observations cover shape flags, intersecting hard
joins, unsupported-source replacement, width/thickness/unified deformation,
Hexagon/rotation, exact archive history, reopen, selection draft reset and profile
search. [Native modeling observations](native-modifier-acceptance.md) records the
actual mesh counts and byte comparisons. These used the existing canonical editor
process rather than the mandated combine-qa bundle, and its loaded revision was
not verified after on-disk rebuilds. Consequently the formal native acceptance
claims in the preceding paragraph remain pending a controlled exact-revision QA
repeat. Linked-profile mutation/history, other indicated history paths, Qt
differential acceptance, VoiceOver and full M3 parity remain pending as well.

- Implement every part/component property in the parity matrix with validated ranges, lock behavior and undo. Add ordered component tree, inspector selection, previews and grouping/reordering.
- Expose generated source IDs and indexed geometry; implement component preview caches keyed by semantic revision. Audit graph assumptions: the current viewer rejects branching/disconnected chains, so do not loosen validation without proving generator support or defining explicit editing diagnostics.
- Add incremental regeneration only after correctness is established. Bound cache memory; discard obsolete work and surface generation failures.
- Done: modifier corpus passes geometry/bounds/normal checks and agreed Qt tolerances; editing combinations round-trip; no unsupported property silently resets.

### M4 — UVs, materials, textures and embedded models

Dependencies: M3, with import preservation already required in M1. Suggested PRs: asset service/import; UV/material ABI; CPU bake extraction; PBR renderer/inspectors.

- Isolate Qt image/resource dependencies from `mesh_generator`, `uv_map_generator` and related services. Prefer portable pixel buffers in C++ and ImageIO/CoreGraphics only at Apple decoding boundaries; preserve existing bake algorithms where possible.
- Expose indexed vertices, UVs, material groups and texture buffers with explicit pixel format/color space/ownership. Implement PBR shading, transparent material ordering, normal/AO/emissive maps and image material controls.
- Port embedded GLB loading and transforms with bounded parsing; decide supported extensions and handling of unsupported ones in an ADR.
- Done: texture/import fixtures render and export correctly; UV seams/material grouping retained; all archive assets survive; malformed images/GLB cannot crash the app.

Color-image document commands under #138 ([ADR 0068](adr/0068-lossless-component-color-images.md)) provide
assignment/removal and atomic bounded PNG import while retaining opaque/shared assets,
source identity semantics and exact history. Real-baker integration verifies
assigned-image output; a shared pure PNG envelope parser preserves the existing
platform decoding boundary. Native import services and inspector controls landed in PR #141 with exact
history, real-bake and native save/reopen evidence. Full M4 acceptance remains
required; neither the foundation nor that workflow claims complete material parity.

### M5 — Rigging and skeletal editing

Dependencies: M3; material/export integration follows M4. Suggested PRs: rig adapter; skeleton overlay/bone inspector; IK/weights.

- Extract portable work from `rig_generator_worker`, `rig_skeleton_mesh_generator`, bone structures and `skeleton_ik_mover`. Model rig parameters and bone edits without Qt types.
- Add skeleton visibility/picking, hierarchy/properties, rig generation progress, rest pose and deformation preview. Define coordinate/axis and joint index conventions once across renderer/exporters.
- Done: valid parent graph and normalized weights; expected rest pose; fixture deformation parity; undoable rig edits persist; failures retain recoverable document data.

### M6 — Animation and procedural audio

Dependencies: M5. Suggested PRs: evaluation APIs; animation management/playback; sound generation and synchronization.

- Add required `dust3d/animation` and `dust3d/sound` code as explicit Qt-free targets; they are not compiled by the current viewer package. Inventory existing animation types/parameters rather than assuming a general keyframe editor.
- Port preview/export worker orchestration into actors. Add animation list and parameter inspectors, playback/time controls, skeleton skinning and audio preview where supported by the reference app.
- Done: sampled poses and durations match fixtures, playback independent of frame rate, sound exports have correct format/duration, stale generation and cancellation do not publish wrong animations.

### M7 — Export and automation parity

Dependencies: M4 for static exports; M5–M6 for animated exports. Static OBJ/GLB can land earlier.

- Extract Qt-independent writers from `glb_file` and `fbx_file`; keep licensing and axis/unit conventions explicit. Provide OBJ, GLB, FBX and model-plus-WAV workflows with asynchronous progress and atomic output handling.
- Add a headless core CLI and/or Apple command entry point compatible with current batch workflows. Share export use cases with UI; never export a stale mesh or report a failed/empty export as success.
- Done: independent re-import verifies geometry, UVs, materials, bones and animations; batch exit codes and diagnostics tested; partial multi-file failures are recoverable and disclosed.

### M8 — Hardening, distribution and parity release

Dependencies: all parity milestones. Split into focused performance, security and release PRs.

- Benchmark corpus load/edit/generate/bake/export latency, peak memory and interaction frame time on Apple Silicon and supported Intel hardware. Establish measured budgets before optimization; profile expensive algorithms and upload/copy costs.
- Instrument new C++ adapters with coverage and ASan/UBSan; fuzz archive/XML/asset parsing and command sequences. Resolve legacy warnings in narrow commits. Evaluate isolated engine worker and hard cancellation/resource limits for untrusted documents.
- Complete keyboard/VoiceOver, appearance, multi-window recovery, file associations and settings checks. Add signed release builds, entitlements/sandbox decision, notarization, versioning, reproducible packaging and upgrade tests.
- Done: no unresolved blocking parity defects; all automated gates green; manual GPU/export/accessibility matrix recorded; editor and viewer packaged separately. Viewer gains compatible shared improvements without acquiring editing behavior.

Namespace-growth hardening for clipboard/asset transfers is implemented locally
under #67 ([ADR 0067](adr/0067-bounded-namespace-transfers.md)): one cumulative
binding/payload budget checks inherited preservation and explicit default binding
allocation before new XML nodes are installed. Review and full-gate results remain
required; this does not establish general parser fuzzing or resource isolation.

## First editor PR after viewer merge

Implement M1's document codec and immutable state with lossless round-trip fixtures, then the minimal command/undo layer. Keep the renderer unchanged in that PR. The first user-visible editor PR follows with a separate app, node movement/radius editing, undo and save. This prevents a convincing canvas from hiding a lossy persistence model.

## Verification and risk controls

- When each PR opens, send the user a current app screenshot when capture is available. Identify the app iteration and whether the visible UI changed. Label offscreen renderer evidence separately; do not present it as an app screenshot. If capture is unavailable, report that limitation without requiring human interaction.
- New pure Swift domain: 100% meaningful coverage; application/infrastructure: at least 95%, with thin native/manual boundaries disclosed. Add a real CI threshold checker rather than relying on the current coverage report alone. C++ adapter coverage is a separate instrumented job; inherited algorithm coverage is a tracked adoption gap.
- Keep formatting, Swift warning errors, explicit C++17 rules, Qt source/link checks and clean-clone builds in both applicable repositories. Test ABI ownership, size arithmetic, malformed inputs and long-running generation. No artificial hooks just to increase coverage.
- Use semantic equality for archives, tolerance-based geometric assertions and independent format readers. Maintain rendered reference baselines on controlled CI machines with human review; do not treat local GPU pixels as portable golden files.
- Biggest risks: lossy snapshot/asset saves, Qt-bound texture/export utilities, fork-specific animation/audio behavior, engine global state, expensive uncancellable generation, and API/version drift after a repo split. Resolve each with an early fixture or spike before expanding its UI.
- Decisions still needed before release: engine fork name/ownership, supported Intel/macOS matrix, exact rig/animation parity list, sandbox/distribution channel and representative large-document budgets. These do not block the initial document/command work.

## Release ordering

1. Review and land the standalone viewer PR; do not merge it automatically.
2. Open document/command foundation PRs against the landed branch and track the parity checklist as issues.
3. Switch Apple app consumption to the established core repository only after standalone build and document/API gates pass; publish engine versions through reviewed releases.
4. Ship editor previews by completed milestone with explicit unsupported-feature behavior. Declare full parity only after M8 acceptance, not after the initial editing UI.

## Upstream relationship and synchronization

The core default branch is `master`; `upstream-sync` contains only upstream commits. Retain upstream file paths and keep new adapters/build/tests separate. The legacy Qt tree remains reference material and is excluded from the core build; deleting it is unnecessary and would increase synchronization conflicts.

Configure `origin` to the core repository and `upstream` to `https://github.com/huxingyi/dust3d.git`. Advance `upstream-sync` by fast-forward only after fetching upstream master. Open a `codex/sync-upstream-*` PR that merges that exact tracking commit into core master. Inspect changes to serialization, vendored dependencies, geometry and licenses; run the compatibility corpus and sanitizer matrix before approval. Never auto-reset maintained master to upstream or force-push a synchronization branch. Record the upstream revision and release contract in each core release. Where a portable fix is suitable, propose a focused PR through the existing GitHub fork; upstream acceptance is optional and must not be assumed.

A sync workflow may check and open a PR when explicitly enabled, but setup does not schedule unattended synchronization or contact upstream maintainers. Check upstream during maintenance/release work. Signed/checksummed core releases and exact dependency pins keep Apple releases reproducible.

## Rigorous core testing program

Yes: separating the portable engine allows tests to run without SwiftUI, Metal, Qt or a display server, independently of Apple app release schedules. Repository separation enables this; the tests and gates still have to be implemented and maintained.

Initial setup provides a standalone CMake/CTest build and headless C API contract tests. CI covers Linux and macOS, with separate address/undefined-behavior sanitizer coverage on Linux. This is a foundation, not a claim of complete algorithm coverage.

Expand in this order:

1. **Trust boundary:** archive offsets/lengths/depth, invalid identifiers/references, nonfinite geometry, unsupported assets, ownership/lifetimes, bounded diagnostics and failure state. Add regression fixtures for every discovered defect.
2. **Document fidelity:** semantic load/save equivalence, unknown fields/assets, version compatibility, malformed inputs, independent Python-produced archives and Qt round trips.
3. **Geometry properties:** finite vertices/unit normals, valid indices, nondegenerate triangles where appropriate, manifold/watertight properties when required by a feature, stable bounds, modifier combinations and permutation/orientation cases. Compare semantics and tolerances rather than incidental vertex order.
4. **Differential corpus:** run known models through upstream and downstream builds; classify intentional differences and fail unexplained regressions. Preserve the upstream executable/version used for each baseline. Add representative real documents with appropriate permission and licensing.
5. **Dynamic analysis:** ASan/UBSan on new and inherited execution paths, leak checks, and TSan once concurrency semantics are implemented. Serialization currently prevents concurrent generation; test concurrent callers without assuming algorithms are internally thread-safe.
6. **Fuzzing:** libFuzzer targets for archive/XML/asset decoding and command sequences, seeded with minimized corpus cases. Use short PR smoke budgets and longer explicitly configured nightly runs; retain crash reproducers as regression tests. Do not add nightly schedules without authorization.
7. **Coverage:** LLVM branch/line reports separated into new adapter and inherited geometry. Establish the inherited baseline first; enforce at least 95% meaningful new adapter coverage and 100% pure validation/domain coverage where testable, with documented boundary exceptions. Block changed-code regressions and track legacy coverage improvement; never claim Swift XCTest coverage measures C++.
8. **Resource/performance:** fixed benchmark corpus, wall time, peak RSS, output size, cancellation and stress tests. Establish budgets on controlled runners; investigate significant changes before shipping. Limits in the current parser do not bound CPU/memory inside geometry generation.
9. **ABI/release compatibility:** compile a pure-C consumer, verify symbols/header layout and ownership against supported released clients, test clean installs, no Qt linkage, required license notices, and both Apple apps against each candidate engine release.

All core dependency upgrades and upstream-sync PRs use the same tests. Keep fixture metadata (source, license, upstream revision, expected behavior, tolerance) next to fixtures. Review intentional baseline changes; do not automatically bless newly generated output. Core release readiness requires documented sanitizer, compatibility and ownership results, not just a successful build.

## Editor foundation progress

The separate viewer and editor apps consume the exact pinned external core package.
The editor now supports node selection/movement/radius editing, interaction locks,
multiselection/marquee/scaling/transforms, topology creation/deletion/splitting/joining,
edge picking/reversal/inspection, explicit descendant-pivot rotation, native clipboard editing, undo/redo, open/save and
resilient mesh previews. Reference-image archive editing, bounded platform import and Qt-aligned canvas
rendering, part-state controls, local/global alignment and origin editing/markers are implemented;
crop/composition and physical origin-gesture QA remain pending; native model-bounds origin centering is explicit (ADR 0023). Verification records linked above state
actual test/native coverage and limits. The M1/M2 acceptance gates still include Qt GUI
interoperability, recovery/failure cases and broader accessibility/performance checks;
M3–M8 feature parity is not claimed.

Descendant rotation implementation and limits are recorded in [verification](descendant-rotation-verification.md) and [ADR 0026](adr/0026-descendant-rotation.md). This does not close the remaining M2 acceptance gates.

Reference-image crop/layout and raster primitives have a [foundation verification record](reference-composition-foundation-verification.md). The composition sheet, transient draft orchestration and atomic Apply/Cancel remain pending in #56; this foundation does not complete cropping/composition acceptance.

The composition sheet, transient async drafts, pointer/numeric selection and stale-guarded atomic image/origin Apply now have [automated tests and partial native evidence](reference-composition-workflow-verification.md). Final-build native Apply/save/Undo, rendered inspection and the app-owned composition recovery command are verified. Held-gesture/VoiceOver and Qt differential acceptance remain pending; #56 stays open. This does not complete M2 or Qt GUI parity.

Native save serialization now guards outstanding edits and superseded snapshots with typed retry diagnostics while retaining the native File menu. [Save verification](native-save-snapshot-verification.md) records controlled publication/failure/cancellation tests, native import/Save rejection and independent Duplicate/Save As; exact native Undo/Save and Redo/Save archive comparisons pass. Broader M1 filesystem recovery acceptance remains pending.

The shared mesh camera now fits portrait previews, including separated parts;
[verification](aspect-camera-verification.md) records the projection regression,
100% pure-camera coverage and native rendered checks. This resolves #73 without
changing core geometry or claiming broader Metal coverage.

Component Normal/Inversion/Uncombined editing now has a typed lossless command,
atomic history, real pinned-core preview tests and a native inspector picker
([ADR 0038](adr/0038-component-combine-modes.md),
[verification](component-combination-verification.md)). Native picker/rendering
and exact Save/Undo/Redo checks pass, including unknown source mode restoration.
Qt differential boolean/modifier corpus remains pending; M3 is not complete.

Component normal smoothing cutoff now has finite 0–180 validation, lossless
commands, real-core normal/geometry tests and explicit native Apply/Reset controls
([ADR 0039](adr/0039-component-smoothing-cutoff.md),
[verification](component-smoothing-verification.md)). Native rendering, invalid
input recovery, reopen and exact Save/Undo/Redo checks pass. Qt differential and
interacting modifier acceptance remain pending; M3 is not complete.


### Wrapping foundation checkpoint (Apple #98)

Typed group-only mode, keep-children, face-count and seven geometry-scalar commands
now preserve source spellings, unknown metadata, opaque content and exact history.
See [foundation verification](component-wrapping-foundation-verification.md) and
ADR 0049. The reviewed core pin includes complete wrapping numeric validation and
portable stitching contracts. Binding and material wrapping features remain pending. Core issue #13 is repaired by reviewed core PR #15; the exact Apple pin and
[controller verification](wrapping-controller-verification.md) cover finite
midpoint openings and straight profiles, validated drafts, real previews and
exact history/save publication (ADR 0050, Apple #100). Genuine failure diagnostics
remain separately tested. Core #14 is repaired at exported float precision by reviewed core PR #16.
Native geometry controls and pure presentation now have [offscreen verification](native-wrapping-verification.md)
(ADR 0051, Apple #102); native interaction, binding/material controls and broader
Qt differential/topology acceptance remain pending. M3 acceptance remains incomplete.


### Indexed Swift boundary checkpoint (Apple #104)

The reviewed core indexed-buffer API now has an exact dependency pin and copied,
Sendable Swift values with strict and optional loading. Native buffer lifetime,
known planar attributes/area, fixture bounds, concurrent ownership and error
semantics are tested; see [verification](swift-indexed-mesh-verification.md) and
ADR 0052. Renderer adoption, source IDs, cache/scheduling improvements and broader
Qt differential acceptance remain pending. M3 is not complete.


### Indexed renderer checkpoint (Apple #106)

Both native apps use copied indexed previews and UInt32 Metal draw buffers, while
expanded SDK and viewport callers remain compatible. Pure buffer preparation and
the production offscreen GPU pass have semantic/solid/wireframe verification;
see [verification](indexed-metal-verification.md) and ADR 0053. Source IDs, bounded
caches, incremental scheduling, materials and broader differential acceptance
remain pending. M3 is not complete.


### Swift session ownership checkpoint (Apple #108)

Dust3DKit now exposes an optional actor-owned core session with copied indexed
output, explicit cache outcomes/diagnostics, reset and cancellation boundaries,
pinned to reviewed core PR #24. See ADR 0054. Editor preview actor adoption and
background encoding/coalescing follow separately; both app loading paths remain
compatible. Source provenance, controlled performance budgets and the broader Qt
differential corpus are still pending. This does not complete M3 or editor parity.


### Editor preview session checkpoint (Apple #110)

The editor now uses the reviewed session SDK with document-scoped ownership,
obsolete-cleanup protection, retained request/cancellation semantics and separate
cache-only diagnostics. See ADR 0055. Existing encoded documents are immutable
Data handoffs; no new encoding/performance claim is made. Source provenance,
controlled memory/performance budgets, broader scheduling acceptance and the Qt
differential corpus remain pending. M3 and full editor parity remain incomplete.


## Swift source-hint SDK stage (#112)

The SDK now pins reviewed cached-source core APIs and exposes independent Sendable
identity/corner/influence values through `generateSourcedIndexed`, with strict UTF-8
and count/range validation, unchanged ordinary loading, cache reuse, separate
budgets and cooperative cancellation. See [ADR 0056](adr/0056-copied-swift-source-hints.md)
and [verification](swift-source-hints-verification.md). Editor preview metadata and
source-based picking follow after review; M3 and broader differential acceptance
remain incomplete.


### Part material parameter stage (#116)

Lossless part metallic/roughness/emissive commands and native Model-part drafts
now preserve reference UI ranges, unsupported metadata and exact undo/save. See
[verification](part-material-verification.md) and ADR 0058. The current preview
does not display these effects. This independent archive/UI stage does not waive
remaining M3 acceptance or complete M4 UV, baking, PBR, color/image or import work.


### Component color stage (#118)

Native component color drafts now preserve alpha-first source notation, unsupported
metadata and exact history while updating actual procedural RGB previews. See
[verification](component-color-verification.md) and ADR 0059. Alpha remains stored
with an opaque preview. Full transparency/PBR, UV/baking/image material/import
work and broader native/Qt acceptance are not complete.


### Copied Swift UV metadata stage (#121)

The exact reviewed core pin now includes numeric packer safety, portable atlas
construction and the owned C metadata boundary. An opt-in SDK copies and validates
triangle-aligned UV/chart/gradient/component metadata into immutable Sendable
values. See [verification](swift-uv-metadata-verification.md) and ADR 0060.
Ordinary/cached preview behavior remains unchanged. Missing mappings, root/broken
chart semantics, texture-aware indexed sharing, pixel baking/PBR/transparency,
image decoding/import/export and full M3/M4/Qt acceptance remain incomplete.


## Copied baked output SDK (Apple #123, landed through #124)

The exact reviewed core pin now includes owned CPU baking. Dust3DKit exposes typed
decoded RGBA8 inputs, copied maps and triangle-aligned tangent frames, with expanded
geometry preserving texture/material seams. MeshBakingService runs work on a
background actor and pins cooperative cancellation through loading/copying. See
[ADR 0061](adr/0061-copied-baked-mesh-sdk.md). Full local gates, automated review and
CI passed before landing #124. Asset decoding, editor scheduling and cached
bake invalidation, seam-aware indexing, PBR/transparency/AO, textured export and
broader M3/M4 acceptance remain subsequent stages; current preview UI is unchanged.


## Retained archive texture decoding (Apple #125, landed through #126)

The existing document parser resolves exact referenced assets without changing
archive bytes. A shared Apple actor decodes PNG samples into straight RGBA8 with
per-image/aggregate limits, preserves asset-specific causes, and feeds the actual
native baker. Independent fixtures cover standard sample families, low/zero alpha
and encoded orientation; full local gates pass (580 tests), with completed clean
exact-head automated review and all three CI checks passing before merge. See
[ADR 0062](adr/0062-retained-color-image-decoding.md). Editor scheduling/cache
invalidation, seam-aware textured indexing, renderer/PBR/transparency/AO and
textured export acceptance remain subsequent stages. This does not complete M4.


## Seam-aware textured render geometry (Apple #127, landed through #128)

Pure Sendable preparation retains triangle-aligned UV/component metadata and maps,
shares only complete corner attributes, and bounds logical/GPU buffer spans. It
reuses ordinary camera normalization. Targeted seam, resource, cancellation and
actual-baker tests and the full local gate pass (587 tests), with 100% measured
line coverage for both pure preparation files. Exact-head automated review and
all remote CI passed before squash merge. See ADR 0063. Metal upload,
material shading, transparent ordering, PBR/AO, app scheduling/invalidation and
textured export remain subsequent work; current app previews are unchanged.

## Owned Metal material renderer (Apple #129)

Following landed #128, the separate production material encoder now implements
bounded actor uploads, transferred noncopyable GPU ownership, color/normal/scalar/
emission sampling, linear blending, opaque depth and cancellable camera ordering.
[Verification](metal-material-renderer-verification.md) records actual pinned-core
bake rendering and independent GPU fixtures. App viewport adoption and bake
scheduling/invalidation are the next integration stage. AO, imports, material
image controls, exports and full M4/Qt acceptance remain incomplete.

## Native material viewport adoption (Apple #131, in progress)

Both apps now locally adopt the reviewed material encoder through the shared
viewport. Bounded background bakes and GPU uploads preserve camera state, reject
obsolete completions and retain ordinary geometry with original failure causes
and retry. Material-only editor edits refresh independently of geometry/history;
the viewer uses one exact bounded archive snapshot. See ADR 0065 and
[native acceptance record](native-material-viewports-verification.md). The full
local gate passes 613 tests; native material edits, history, save/reopen,
wireframe, camera and automatic first-frame checks pass. Automated review and
remote CI remain required before merge; this does not complete M4.

## macOS rendered file previews (Apple #132, required)

The user requires rendered `.ds3` previews outside the app. Prioritize this after
native material viewport adoption (#131), before unrelated editor features.
Implement both a Finder thumbnail provider (`QLThumbnailProvider`) and a Quick
Look preview extension (`NSViewController` conforming to `QLPreviewingController`).
Show the actual object through the shared Qt-free pipeline; a generic app icon
is not acceptance. Quick Look is read-only, with orbit/zoom/fit where supported
and a rendered static fallback when necessary.

- Existing archives must work on demand without a re-save. Investigate upstream
  embedded preview conventions before optionally using them; `canvas.png` is a
  reference image and must not masquerade as a rendered model thumbnail.
- Match requested dimensions, scale and aspect; fit a deterministic camera and
  background, preserve color/alpha semantics and reject malformed or oversized
  inputs. Budget extension work, handle cancellation and unavailable GPU cases,
  and never write the source file, use the network or depend on editor state.
- Unify document-type declarations and select one owning app bundle to avoid
  competing providers when viewer and editor coexist. Keep shared sources and
  dependencies in SwiftPM; document deterministic `.appex` build/embedding,
  resources, entry points, entitlements, signing and OS discovery. A standalone
  SwiftPM executable is not evidence of registered Quick Look support.
- Verify actual Finder icons/gallery/preview-pane behavior, Quick Look Space-bar
  rendering, applicable native open panels, and rebuild/install/upgrade behavior
  without stale registrations. Test independent recognizable models, textured,
  empty, malformed and large files, and unchanged source bytes after preview.
- Include automated framing/render/lifecycle tests and native screenshots with
  the PR. Offscreen images alone do not prove Finder integration. Full local
  gate, final-head review and all remote CI must pass before merge. Distribution
  signing/notarization and platform limits must be reported honestly.

References: [Apple thumbnail extensions](https://developer.apple.com/documentation/quicklookthumbnailing/providing-thumbnails-of-your-custom-file-types)
and [Quick Look UI](https://developer.apple.com/documentation/quicklookui/).

Local implementation for #132 now packages both providers in the editor, with
shared bounded loading and production Metal rendering. Native acceptance renders
Sword in Quick Look (including wireframe), Finder icons and gallery; public system
thumbnail requests render two independent fixtures. Regression tests cover
background callback isolation and Retina bitmap sizing. Full local validation
passes 627 tests. Automated PR review and remote CI remain required before merge;
broader textured/empty/error/open-panel and install/upgrade acceptance must retain
its explicit evidence rather than be inferred from an offscreen render.

## Native component color-image workflow (Apple #140)

The inspector now imports PNG/JPEG/BMP/GIF/TIFF, chooses unused or shared retained
images and clears overrides without removing assets. Actual pixels are validated
in the background before one lossless history step; selection/edit/replacement
and cancellation invalidate obsolete requests. Material-only commands refresh
bakes without rebuilding geometry. See [ADR 0069](adr/0069-native-component-color-images.md)
and [verification](native-component-color-images-verification.md). Native import,
retained selection, clear, history and save have current working-tree observations;
the final accessibility rerun passes. Final-head review/remote CI remain required. Textured
exports, wider material/reference parity and the remaining M4–M8 work are open.

## Remaining milestone tracking

These epics preserve the full goal and are not a count of implementation PRs.
Split them into focused issues as the actual core/native contracts are established.
Existing native modeling acceptance (#120) and the hollow-thickness decision (#96)
remain open; UI presence or passing unit tests alone do not close those gates.

| Milestone | Tracking | Required remaining evidence |
| --- | --- | --- |
| M4 materials/imports | [#143](https://github.com/dalbrecht/dust3d-swiftui/issues/143) | Material/reference parity, embedded GLB, malformed assets and textured export integration |
| M5 rigging | [#144](https://github.com/dalbrecht/dust3d-swiftui/issues/144) | Portable rig/IK contracts, native editing, weights/rest poses and deformation fixtures |
| M6 animation/audio | [#145](https://github.com/dalbrecht/dust3d-swiftui/issues/145) | Actual upstream types/parameters, evaluation, playback, synchronization and WAV correctness |
| M7 export/automation | [#146](https://github.com/dalbrecht/dust3d-swiftui/issues/146) | Independent re-import of static/textured/rigged/animated outputs and recoverable batch failures |
| M8 production release | [#147](https://github.com/dalbrecht/dust3d-swiftui/issues/147) | Measured performance, C++ instrumentation/fuzzing, accessibility/recovery and signed upgradeable separate apps |

Cross-app representation-aware compatibility notices are tracked in #142; see
[ADR 0070](adr/0070-shared-material-preview-notices.md). The remaining milestone
epics must not be closed when only their first API or inspector stage lands.

## Runtime provenance and QA packaging (#136, in progress)

A local implementation embeds immutable source/core identity in each executable,
exposes a startup capture in About diagnostics, and adds a repeatable packaging
path for the existing combine-qa identity without competing preview providers.
[ADR 0071](adr/0071-immutable-runtime-build-identity.md) records boundaries and tests.
[Local validation and native diagnostics inspection](runtime-build-identity-verification.md)
pass; reviewed delivery remains pending. Formal
M3 native/Qt acceptance under #120 is not established by this instrumentation.

### Imported material ownership follow-up (issue #153)

Core geometry #43 and owned material/image API #47 are merged. The Apple adoption
stage pins `4db1bb770b4c342446805f77ccfa4dc0aabc90c4` and adds independent Swift
metadata/image copies plus bounded background PNG/JPEG decoding (ADR 0072).
Material factors are retained separately from source pixels. Its validation must
include exact asset preservation through edit/undo/reopen and real imported
geometry loading; metadata/decoded pixels do not establish rendered parity.
Imported corner UV/Boolean/cache propagation, bake integration, PBR/alpha display,
fully rendered Quick Look/thumbnails and textured-export re-import remain open M4
acceptance work. The full editor plan remains incomplete.
