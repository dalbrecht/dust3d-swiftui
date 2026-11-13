# Qt parity and macOS acceptance matrix

Checkpoint: November 6, 2026, merged Apple `0243cfca` (#382). Full requirements
remain [editor-port-plan.md](editor-port-plan.md), including M0–M8 and its
verification/risk controls. This matrix groups those requirements by acceptance
boundary; rows are not equal-sized features or a completion denominator.

**Implemented** below means current source has a route. **Scoped evidence** means
only the named fixtures/tests/contracts support it. Neither status means full
parity, physical interaction acceptance or readiness for general distribution.
Unknown or missing evidence remains open. The baseline includes #382 subtraction; broader physical modifier acceptance remains open.

## Requirement reconciliation

| Required behavior | Current authoritative route/evidence | Missing proof or capability |
| --- | --- | --- |
| Complete Qt action, serialization and animation/sound inventory | Qt reference at production core `48b0ce2d`; `document_window.cc`, `skeleton_graphics_widget.cc`, component/part/bone/animation widgets; native symbols and ADRs below | Inspected literal and activated subsets do not cover every dynamic action, reader/default, legacy alias or archive asset family. Full M0 checklist/corpus is open. |
| New/open/save/save-as, dirty state, duplicate, recent files and asset retention | `EditorFileDocument`, `DocumentGroup`, document codec and snapshot save guard; [save evidence](native-save-snapshot-verification.md) | Actual OS menus, recent/close/cancel, external file changes and Qt→native→Qt corpus; framework ownership is not accepted merely by source presence. |
| Atomic saves, autosave/recovery and retained originals/history | Accepted snapshot save; [bounded recovery copies](adr/0093-bounded-editor-recovery-copies.md), lossless unknown XML/assets | Physical lifecycle/recovery and broader OS failure acceptance; private recovery copies are not universal crash recovery. |
| Add/connect/delete/reverse/reduce/midpoint graph edits | `EditorState`, `GraphSelectionActionTarget`, `NodeConnectionControls`; [context ADR](adr/0174-canvas-context-actions.md) | Broad Qt differential and physical context/keyboard workflows. Qt Split here means midpoint insertion, not disconnect. |
| Independent node/edge selection, marquee, clipboard and per-window Undo/Redo | `EditorState.selectGraph`, `CanvasProjection`, `removeFromSelection`, `EditorClipboardCommands`, native undo routing; existing selection/clipboard tests | Physical focus/modifier/multi-window acceptance. Subtractive selection is implemented, with [scoped evidence and limits](adr/0176-subtractive-graph-selection.md). |
| Front/side moves/scales/radius, quarter turns/flips/XZ exchange and alignment | `SelectionTransform`, `CanvasPrecisionActions`, origin commands and selection tests | Interacting numeric/locked/differential cases and actual keyboard/text responder acceptance. Names alone are not additional missing commands. |
| Continuous gestures, Escape, stale results and responsiveness | Token/epoch-based input, `CanvasPointerActivity`, preview scheduling and existing regression contracts | Held physical gestures, window/focus changes, load/close/replacement and large-document responsiveness. Pure cancellation callbacks do not prove event delivery. |
| Front/side reference import/crop/mirror/swap/composition | `ReferenceCompositionSheet`, isolated draft/service/raster; [workflow evidence](reference-composition-workflow-verification.md) | Complete Qt raster/format corpus and physical dialog, cancel, resize and multi-window acceptance. |
| X/Y/Z/radius locks; part visibility/lock/disable; origin and mirror | Native constraints and part/origin controls; [global visibility ADR](adr/0175-canvas-hide-all.md) | Broad interaction combinations and physical acceptance. Canvas hiding must not be confused with mesh-disabled state. |
| Ordered hierarchy, naming/group/ungroup/reparent/delete/part roles | `ComponentSidebar`, batch component targets/commands and hierarchy tests | Larger hierarchy/asset/namespace Qt reopen corpus and physical drag/keyboard/accessibility paths. |
| Combine/smoothing and procedural modifier families | Part deformation/profile/modifier, component mesh/stitching/wrapping/surface controls; [controlled comparisons](controlled-native-modifier-acceptance.md) | Per-family and interacting topology numerical comparisons, generated/reopened fixture corpus and production hollow consumer acceptance (#96/#120). Stored fields are not proof of generator adoption. |
| Colors/images, transparency/metalness/roughness/emissive, countershade/detail, UV and baked maps | Native material/color/image/source-bake/render routes; [material evidence](imported-material-editor-verification.md) | Complete UV/PBR/alpha/mip/differential rendering/export proof and intended color-space correctness across every route (#143). |
| Embedded GLB assets/transforms/materials and supported references | Lossless assets plus bounded import/material routes; [mixed file evidence](mixed-file-preview-verification.md) | Complete malformed/unsupported corpus and containment; no partial output may be claimed complete. GLB quarantine remains. |
| Rig type/eyelid/bone assignment, hierarchy/weights/skeleton and IK | Stored authoring/assignment/progress/hover; graph endpoint IK; experimental generated-rest hierarchy/weights/joint viewport | Production actual-rest adoption, Qt joint/weight/rest comparison, evaluated skeletal deformation and physical viewport acceptance (#144). Graph endpoint IK does not establish all skeletal evaluation. |
| Animation name/type/parameters, generation and elapsed-time playback | `DocumentAnimation`, catalog-backed authoring; pure `AnimationTimeline` projection | Evaluated owned frames/poses, skinning, scrubbing, playback independent of callback rate, cancellation and stale publication; native panel explicitly states playback unavailable (#145). |
| Procedural sound, synchronization and WAV workflows | Stored `surfaceMaterial` authoring; Qt `animation_manage_widget.cc`/preview worker/sound sources define the reference intent | Native sound generation/adoption, format/duration, synchronized preview and WAV output remain unaccepted. A stored surface choice is not audio playback. |
| Static/textured/rigged/animated OBJ/GLB/FBX and combined WAV export | `EditorGeometryExportCommands` and `DocumentExportFormat` expose OBJ/FBX geometry routes with captured source/publication admission | Full format families, materials/UV/rig/animation/audio and independent consumer re-import; writer/GLB quarantine remains (#146). |
| Headless/batch behavior, exit diagnostics and partial multi-file recovery | Export ownership/coordinator foundations; source save differs from export | End-to-end batch and recoverable publication corpus; local helpers are not automation acceptance. |
| Desktop menus, toolbars/inspectors, camera/display modes and settings | Native commands, `InspectorCommands`, standard About, Help/credits, preview palettes/camera routes and documented shortcuts | Actual menu/focus dispatch, customization, Full Keyboard Access, VoiceOver, contrast/appearance/Reduce Motion and supported OS/hardware scenarios. See physical criteria below. |
| Worker containment, lifecycle, memory/performance and distribution | Scoped core coordinator/local worker contracts; Qt-free builds, package identities/resources, ad-hoc signatures/exact archives | Separate new-C++ adapter coverage, ASan/UBSan and archive/XML/asset/command fuzzing; strong memory/descendant/filesystem/network/parent-death containment and stop/escalation; measured load/edit/generate/bake/export latency, peak memory and interaction budgets on supported Apple Silicon/Intel/OS hardware; file associations, settings, entitlements/sandbox decision, signing/notarization, versioning/reproducible packaging and upgrade/distribution (#147/core #123). Metadata is not a sandbox. |

## Signed canvas acceptance evidence

The local QA tag `mote3d-master-qa-20261112.7` points to App
`bf48642a9` (#676) with Core `48b0ce2d`. The canvas tests cover
visible node outlines in both profiles, overlapping node and tapered edge
precedence, and whole-part selection. The full local run recorded 2,304 XCTest
cases, including two skips and zero failures. Hosted checks passed before merge.

The signed local candidate `mote3d-canvas-add-input-candidate-qa-20261112.1`
points to App `f027bba41` with the same Core revision. Its tests cover
Command-double-click Open on blank space, geometry precedence, stale document
callbacks, hover-radius edits with sidebar selection, and Add chain reprojection
after a resize. The full local run recorded 2,305 XCTest cases, including two
skips and zero failures. The changes are under review in #677, #617 and #618.

Both builds passed archive signature and checksum verification, Finder provider
bundle verification, and a byte-exact headless OBJ comparison for the batch
scaling fixture. Physical pointer, keyboard-only and VoiceOver checks remain
open for these canvas workflows.

## Signed static export comparison

Standard QA `.48` uses Core `48b0ce2d`. The signed local QA tag
`mote3d-mirrored-fbx-qa-20261112.1` records App `ec975c09`,
Core `9027e031`, and the archive checksum.

- The isolated Editor exported and independently reimported all 11 procedural
  textured FBX fixtures. Standard QA failed six of those fixtures.
- The mirrored textured capsule reimported with 312 triangles and an embedded
  PNG. Save and reopen preserved its positions, UV coordinates, and texture.
- The displaced concave OBJ matched all 70 Qt polygons in winding and
  connectivity. The coplanar case exported a closed mesh at the fixture's
  expected volume. Qt exited with a Boolean failure on that case.
- Sword retained equivalent surface geometry across two FBX triangulations.
  Nearest-texel samples differed by at most two 8-bit levels on the sampled
  points. Filtering across mip levels and physical preview remain unverified.

These fixtures exercise ordinary headless export and reimport. Production
Core adoption and the remaining export families are still open.

## Source correspondence anchors

Inspected activated M3/non-quarantined M5 families map as follows. Qt paths are
under `application/sources` in `dalbrecht/dust3d-core`; they are not linked by the
native app. The inspected widget files are byte-identical to production core
`48b0ce2d`. Line references are source navigation aids, not executed acceptance.

| Qt reference | Native counterpart |
| --- | --- |
| `skeleton_graphics_widget.cc:238–369` graph context edits/transforms | `GraphSelectionMenu`, `GraphSelectionActionTarget`, `SelectionTransform`, connection/alignment controls |
| `skeleton_graphics_widget.cc:1047–1075` Shift-drag/endpoint IK | `CanvasShiftDrag`, `EndpointIKTarget`, `EndpointIK` |
| `part_manage_widget.cc:294–433` hierarchy actions | `ComponentSidebar` and captured group/order/ungroup/delete/role controls |
| `component_property_widget.cc:165–973` modifier/material/wrapping controls | Part deformation/profile/modifier/material and component mesh/stitching/wrapping/surface controls |
| `bone_manage_widget.cc:222–375`, `:554`, `:663–673`, `:868` authoring/selection | `RigSettingsControls`, `RigTemplateBoneBrowser`, `BoneEdgeOverview`, assignment/clear targets |
| `bone_manage_widget.cc:765`, `:943` generated-rest inspection | Experimental `GeneratedRigPreview`, hierarchy/weights/joint inspection; unpublished local-core dependency |
| `animation_manage_widget.cc:227–269`, `:578–581`, `:1093` generation/playback | Actual capability gap; stored authoring and a pure timeline do not supply these routes |

## Physical macOS acceptance criteria

Apple's [macOS guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
expects menu access, keyboard workflows and appropriate native interaction.
Its [focus guidance](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection)
requires coherent selection/focus behavior; source use of standard controls alone
does not establish the resulting interaction.

For each applicable primary journey above, acceptance must record the exact
candidate/source/core identity and the observed outcome for:

- Pointer and keyboard-only completion, including Full Keyboard Access;
  text fields retain text editing/Undo while graph commands affect only their
  intended window/selection.
- VoiceOver labels, values, named actions, traversal/order and status/error
  announcements; a count of accessibility modifiers is not sufficient.
- Selection versus focus, dialog/sheet/default/cancel behavior, Escape during
  gestures, source replacement/close and two-window ownership.
- Light/dark and increased contrast, Reduce Motion, resizing and supported
  hardware/OS rendering; performance must use representative document budgets.
- Save/reopen/export/current-result behavior and an honest result after failure,
  cancellation or unsupported input. Preserve original documents and recovery data.

These scenarios remain outstanding where no current physical receipt exists.
Do not run a forbidden AX replay or control the protected QA process to fill the
matrix. Core #67/#69/#83/#84/#95 and Apple #199 remain quarantined; publication,
production pin changes and rejected core CI retries are not authorized by this
inventory. New sanitizer/fuzz/containment probes require their applicable authorization; this inventory does not grant it. Separate editor/viewer packaging and the viewer’s read-only boundary remain required. No milestone is closed by this document or by an all-green test suite.
