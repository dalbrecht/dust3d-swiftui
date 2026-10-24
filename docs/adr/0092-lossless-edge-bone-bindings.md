# ADR 0092: Lossless edge bone bindings

Status: local implementation, #247, part of M5 #144.

## Context

The reference Document::setEdgeBoneName stores an edge string; toSnapshot emits
nonempty boneName and loading restores it. The inherited rig generator looks up
those exact names to associate model-edge endpoints with bones. Binding is stored
intent, distinct from accepted native bone generation or normalized weights.

## Decision

Expose the exact name in DocumentEdge and add setEdgeBoneName to the existing
immutable document command API. Empty clears the attribute. New names have a
1024-UTF-8-byte limit and reject control/newline/invalid XML characters. Preserve
leading/trailing spaces and case because normalization could retarget identity.
Reads retain all legacy spellings without rewriting or enforcing new-edit limits.

Both endpoints must satisfy the existing editable-part rules, as with edge removal
and reversal. Missing/read-only targets reject atomically with invalidNode; invalid
names use invalidBoneName and an explicit editor message. Preserve every unrelated
XML attribute, rig child and opaque archive item. Existing session batch/history
and immutable edge snapshots carry the command without another state store.

## Validation and limits

Tests first failed on the missing field/command. Focused tests cover exact/empty/
legacy names, XML escaping, Unicode byte limits, forbidden scalar values, independent
read-only endpoints, no-op redo, exact history/reopened storage, unknown XML/assets,
atomic session rollback and retained selection/locks. One initial test incorrectly
assumed ImportedModel metadata alone made a part read-only; inspection established
that inherited editor visibility/lock/disabled flags govern editability. The fixture
was corrected to those rules, without changing target-role editing policy.

The document foundation calls no native evaluator, pose, animation, GLB or quarantined
API and changes no core pin, dependency, CI or renderer. Inspector adoption follows
below. Actual bone existence,
weights, deformation and native interaction acceptance remain separate M5 gates.

## Native inspector adoption

A dedicated EdgeBoneBindingControls view owns only its text draft. Apply/Return
sends an explicit command through EditorStore and the existing serialized session;
Clear removes the binding. Escape/Reset changes only the draft. Selection identity,
accepted name and document replacement reset the draft. Existing editability and
busy state disable the controls. Semantic no-op Apply is disabled.

The inspector explicitly explains that assignments are saved and rigged preview
is unavailable. It does not display fabricated bone validation or weights. System
controls/colors, focused text-editing routing and accessible action labels match
the existing inspector. A controller regression first failed on the missing store
entry point, then covers unchanged ordinary mesh positions/camera, exact history,
selection, no-op publications, invalid edits, Clear and stop. Light/dark unassigned,
bound and read-only inspector renders do not publish edits. Native interaction and
full-gate evidence are recorded separately before publication.

## Delivery integration

Replayed the saved document and inspector stages onto merged rig inspector #255.
The additional controller regression first observed three preview requests instead
of one after Apply/Clear, and changed preview/material revisions. Bone assignment
setters now use the existing metadata-only operation path, preserving accepted
document publication while skipping direct geometry/material regeneration. The
regression also checks camera/selection, exact history and unchanged mesh positions;
generic Undo/Redo keeps its existing ordinary refresh behavior. Full rebased gate
and current diagnostic render review remain pending. Historical native evidence
continues to identify its original runtime; it is not a new native acceptance pass.

## Interface review (full mode)

Scope: the native SwiftUI edge-assignment field and Apply/Clear/Reset controls,
inside the existing 250-point EdgeInspector. Existing semantic system colors,
text styles and native button/field presentation are retained. Offscreen renders
cover unassigned, bound and read-only light/dark states; they do not establish
native keyboard, VoiceOver or File-menu acceptance.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | Bound-light and read-only-dark inspector renders; field/caption source | Clear; exact name remains editable and explanations wrap within the inspector |
| Surfaces | Native field/buttons, disabled state and section divider | Clear; existing desktop styling and readable static capability notice |
| Animations | Control source | Clear; no custom animation added, so slowed-motion review is inapplicable |
| Icons | Control source and inherited locked-endpoint notice | Clear; no new icon system or asset introduced |
| Performance | Controller red/green request-count and revision assertions | Direct assignment edits no longer regenerate ordinary preview/materials |

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | Sources/Dust3DEditor/App/EditorStore.swift:setEdgeBoneName | Apply/Clear unnecessarily requested new geometry and material previews | Use the existing metadata-only serialized operation path | Keep feedback immediate for stored intent without invoking unrelated evaluation |

| Location | Candidate | Rejected because |
| --- | --- | --- |
| Bone assignment field | Offer a generated-bone dropdown | The native bone catalog/evaluator is unavailable; fabricated choices would imply unsupported capability |
| Apply/Clear/Reset | Add custom animation or bespoke button styling | Native feedback matches the existing inspector and repeated edits need no added motion |

Verification: the focused controller/render suite passes two contracts; six light/
dark images were generated and bound-light/read-only-dark were inspected. The
full rebased gate remains separate. No actionable static polish findings remain.
Verdict: Approve inspected static presentation and controller behavior; native
keyboard, VoiceOver and Save/Clear/history/reopen remain **not verified**.
