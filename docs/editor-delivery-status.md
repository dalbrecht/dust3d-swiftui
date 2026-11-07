# Native editor delivery and acceptance status

Snapshot: November 6, 2026. Scope remains the complete M0–M8 plan in
[editor-port-plan.md](editor-port-plan.md). This is an evidence checkpoint,
not a Qt parity, Apple HIG or release signoff. The requirement-level distinctions
are in [the acceptance matrix](parity-acceptance-matrix.md).

## Current baselines

- Merged Apple baseline: `0243cfcaeb81a037225ebb39a473db003b30404e` (#382).
  It includes canvas context editing, interrupted-marquee cleanup, scoped
  isolation, global Hide All Parts and Command-Option subtractive selection. The earlier October 25 baseline and
  pending-publication descriptions in this file are superseded.
- Production core remains `48b0ce2d6d61cf58731bb0c3e14ef5965a686d68`.
  Local core work is not a dependency upgrade or production adoption.
- QA57 was compiled at `f99c87e70678b8dd21fcac1583c26ece5b043019`;
  its complete tree equals the reviewed #382 head and merged baseline.
  Full local validation passed 71 support tests and 1,906 XCTest tests
  (two expected accessibility skips, zero failures), required coverage,
  Qt-free linkage and signed bundle/archive rebuilding. All exact-head public
  checks passed and automated review completed without unresolved findings.
- QA57 and experimental .15 package checks passed. The latter compiled the
  generated-rest configuration against unchanged local-only core and passed
  16 focused pure/model/copied-store/pointer-state tests. This does not establish
  whole-app local-core modeling, evaluated animation or physical acceptance.
  Earlier QA56 counts (1,899 XCTest tests) describe #381, not this baseline.
- Local QA tags and verified archives are development checkpoints. They are not
  published GitHub Releases, notarized distribution or physical acceptance.
  QA52 remains the designated default; no protected existing QA process was
  controlled to establish this checkpoint.

## Milestone evidence and gaps

| Milestone | Implementation/evidence established | Acceptance still open |
| --- | --- | --- |
| M0 — Baseline/inventory | Native editor/viewer separation; activated menu, canvas, component and bone authoring source comparisons. The inspected Qt UI files match the unchanged production-core reference. | Complete action/serialization/type matrix and licensed differential corpus; source correspondence is not behavior equivalence or a feature percentage. |
| M1 — Document/persistence | Lossless document/history, bounded archives, native snapshot save guards and accepted-state recovery-copy foundations. See [save verification](native-save-snapshot-verification.md) and [recovery ADR](adr/0093-bounded-editor-recovery-copies.md). | Qt reopen of native-created corpus; physical save/close/cancel/recovery and OS failure behavior. Simulated writers do not establish every filesystem failure. |
| M2 — Canvas/editor | Graph creation/join/removal, explicit node/edge selection, transforms, front/side editing, reference composition, per-window history, captured context edits, global/scoped visibility and subtraction. See ADRs [0174](adr/0174-canvas-context-actions.md), [0175](adr/0175-canvas-hide-all.md) and [0176](adr/0176-subtractive-graph-selection.md). | Physical held-gesture cancellation, keyboard/VoiceOver, multi-window focus and native-created capsule/sword Qt round trips. |
| M3 — Modeling | Hierarchy, ordering, batch mesh modifiers, deformations, cut profiles, stitching and wrapping have native commands/controls and scoped tests. See [controlled modifier acceptance](controlled-native-modifier-acceptance.md). Endpoint Shift-drag IK also has a native graph-editing counterpart. | Broad interacting topology/modifier numerical comparisons. Hollow #96 includes local work, but its implementation is not implied by the production pin or a visible stored field. Full #120 acceptance remains open. |
| M4 — Materials/imports | Source-aware material/texture/import routes and rendering foundations, plus staged owned source-mip work. See [material evidence](imported-material-editor-verification.md) and [file preview evidence](mixed-file-preview-verification.md). | Complete UV/PBR/alpha/source-mip/export comparison and malformed-asset containment; local core contracts do not establish production adoption. #143 remains open. |
| M5 — Rigging | Stored rig/eyelid intent, exact edge assignments, clear bone/chain, matching/unassigned selection, progress and hover are implemented. Experimental generated-rest preview has hierarchy, weight colors, joint inspection, picking and camera controls. See ADRs [0163](adr/0163-generated-rest-preview-surface.md), [0165](adr/0165-generated-joint-inspection.md), [0168](adr/0168-generated-rest-picking.md). | Experimental actual-rest work requires unpublished local core; production adoption, executed Qt rest/weight comparison, evaluated deformation and physical acceptance are unproven. Preserve Apple #199. Endpoint graph IK is distinct from complete skeletal pose/deformation acceptance. |
| M6 — Animation/audio | Stored animation create/name/type/duplicate/delete and catalog-backed parameter authoring; pure elapsed-time sample projection. See [authoring ADR](adr/0119-catalog-backed-animation-authoring.md) and [timeline ADR](adr/0120-elapsed-animation-timeline.md). | Native evaluated frames, skinning/playback/scrubbing, synchronized procedural sound and WAV workflows. Metadata controls and a pure timeline do not supply these capabilities. Preserve core #95. #145 remains open. |
| M7 — Export/batch | Captured, admitted OBJ/FBX geometry export routes and parent-owned publication coordination. Save remains distinct from export. | Complete textured/rigged/animated OBJ/GLB/FBX/WAV outputs, independent re-import, batch behavior and recoverable partial multi-file publication. No GLB/writer quarantine is lifted. #146 remains open. |
| M8 — Hardening/release | Measured Swift gates, Qt isolation, identities/resources, local ad-hoc signatures and exact archive verification; standard About/credits/help and native command foundations. | Physical keyboard/VoiceOver/HIG, GPU/OS/hardware/performance matrix, separate C++ coverage/sanitizers/fuzzing, strong worker containment/lifecycle evidence, signing/notarization, upgrade and distribution acceptance. Native PR CI does not imply legacy release CI succeeds. #147 remains open. |

## Next delivery gates

1. Preserve serial exact-head CI/review gates for subsequent changes. Retain
   recoverable source and candidate archives; delete only proven clean merged
   worktrees and inactive generated caches.
2. Reconcile the remaining M0 requirements with concrete implementation and
   acceptance evidence. Do not add duplicate controls because Qt names differ,
   or mistake unused Qt helpers for activated product requirements.
3. Advance the actual M4–M7 capability gaps through reviewed core/application
   boundaries, respecting the unchanged production pin and runtime restrictions.
   Stored intent, a local ABI or an experimental viewport is not production
   evaluation, playback, audio or export parity.
4. Obtain actual physical/differential acceptance before closing milestones.
   Source review and green tests cannot establish full Qt behavior or Apple HIG.

Every public merge still requires the full local gate, completed clean review of
its exact head, every current check green and zero unresolved findings. Preserve
core #67/#69 (GLB), #83 (writer), #84 (fault/crash/exhaustion), #95 (animation) and
Apple #199 quarantines. Do not replay the disabled AX fixture, control the
protected QA app, retry the rejected broad core CI matrix or change the core pin
as part of this status reconciliation. Strong containment remains under core #123.
