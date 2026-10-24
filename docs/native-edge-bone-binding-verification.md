# Native edge bone assignment verification

Tracks #247 / M5 #144; see ADR 0092. This is assignment editing and persistence,
not accepted native rig evaluation or weights.

## Automated evidence

The controller test first failed because EditorStore.setEdgeBoneName was absent.
It now verifies Apply/Clear/rejection, unchanged ordinary mesh positions/camera,
selected edge, exact undo/redo, no-op publications and stopped-store rejection.
The fixture is an ordinary two-node procedural chain, without rig/pose evaluation.

Offscreen light/dark renders of the actual EdgeInspector cover unassigned, bound
and read-only endpoints at 250-point width. PNGs are diagnostic artifacts in the
single build root ui-qa/edge-bone, not committed pixel baselines. Rendering does
not change archive bytes or history. Bound light and read-only dark images were
inspected for readable text, fit and disabled controls.

## Native interaction

Pending the fresh, clean QA bundle pass. Reuse org.dust3d.editor.combine-qa;
never overwrite its running bundle or use a new QA ID. Preserve all owned saved
documents and use a disposable ordinary fixture with unknown metadata and an
opaque asset. Verify draft reset, Apply/Clear, exact history saves and reopening.
Full evaluation, Qt deformation equivalence, VoiceOver and supported-OS acceptance
remain separate requirements. Pins and quarantines are unchanged.
