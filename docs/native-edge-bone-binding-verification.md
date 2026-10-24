# Native edge bone assignment verification

Tracks #247 / M5 #144; see ADR 0092. This is assignment editing and persistence,
not accepted native rig evaluation or weights.

## Automated evidence

The controller test first failed because EditorStore.setEdgeBoneName was absent.
It now verifies Apply/Clear/rejection, unchanged ordinary mesh positions/camera,
selected edge, exact undo/redo, no-op publications and stopped-store rejection.
The fixture is an ordinary two-node procedural chain, without rig/pose evaluation.
The rebased regression counts preview requests and checks preview/material revisions;
direct assignment edits use the metadata-only path, while generic Undo/Redo retains
its existing refresh behavior.

Offscreen light/dark renders of the actual EdgeInspector cover unassigned, bound
and read-only endpoints at 250-point width. PNGs are diagnostic artifacts in the
single build root ui-qa/edge-bone, not committed pixel baselines. Rendering does
not change archive bytes or history. Bound light and read-only dark images were
inspected for readable text, fit and disabled controls.

## Native interaction

The prior owned QA app quit normally through its existing app command. A fresh
bundle reused `org.dust3d.editor.combine-qa` and the same shared app-qa path.
About diagnostics confirmed clean loaded source
`ed6fbd1e1e43da207e761fd13d6ece7c3e87610c`, digest
`3c673a6f212da3f08d233be48d9e7449d7254445d76bc035c903068b7ad86242`,
core `41af7d4c1b67dd037e02858e3ef0fdb96a84aebb`, PID 68751 and capture
`2026-10-24T00:06:13Z`. No running bundle was overwritten.

The disposable NativeBoneBindingQA-20261023.ds3 is an ordinary intersecting-parts
copy retaining unknown metadata and opaque.bin. It opened with 370 triangles.
Selecting the first edge exposed the named field and accessible Apply/Clear/Reset
controls. Typing DraftOnly and Escape restored the empty field and disabled Apply;
the saved archive remained byte-exact baseline. Typing Root and Return showed
Root, enabled Clear and enabled Undo.

The control helper then timed out reading the window. A fresh AX read, screenshot
and one Escape recovery attempt also timed out, while app inventory and read-only
process inspection still found the owned process. The attempted Save was not
established: independent file inspection still matched baseline rather than the
pure expected Root archive. Preserve the running process and its potentially
unsaved edit; do not force quit or overwrite its bundle. No human action was
requested. No cause has been isolated to product code versus control infrastructure.

Native Save/Clear/history/reopen and a current whole-app screenshot are therefore
**not passed**. No speculative product fix or complete native acceptance is claimed.
Runtime JSON, exact baseline/expected archives, generator source and logs are
retained in the recovery checkpoint. The offscreen inspector images above remain
diagnostic evidence with their own scope. Full evaluation, Qt deformation
comparison, VoiceOver and supported-OS acceptance remain separate requirements.
Pins and quarantines are unchanged.

## Current delivery gate

The rebased stage on merged rig inspector #255 passed full `make ci` on
9d122694: 36 build-support tests and 911 XCTest cases, zero failures or reported
skips (119.887s), formatting, coverage, Qt-link and isolated packaging/provider
checks. The metadata-only preview regression failed first, then its controller
fix passed. This rerun does not retag the historical native interaction capture
above or establish the remaining native Save/Clear/history/reopen acceptance.
Domain coverage is 35/35 compiler-attributed lines and 17/17 regions; control
coverage is 89/100 lines and 11/19 regions, with native callback/focus gaps.
