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
generic Undo/Redo keeps its existing ordinary refresh behavior. The full rebased gate
and current diagnostic render review are recorded below. Historical native evidence
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

## Rebased full gate

Full `make ci` on stable clean 9d122694 passed 36 build-support tests and
911 XCTest cases, zero failures/reported skips (119.887s), plus formatting,
coverage, Qt-link and isolated bundle/provider checks. No source changed during
this gate. Six current diagnostic inspector renders were regenerated; the scoped
light/dark review above remains distinct from native interaction acceptance.
Compiler-attributed EdgeBoneBinding coverage is 35/35 lines, 17/17 regions and
9/9 functions. The control measures 89/100 lines and 11/19 regions; native action
and focus callbacks remain uncovered, below the later UI coverage adoption target.
Swift branch coverage was not instrumented. These are scoped results, not full
editor or inherited-engine coverage. The original SVG test side effect was
restored after the terminal gate. Final follow-up changes verification prose only.

## Review correction: exact Unicode identities

Automated finding 4365761098 showed that Swift String canonical equality merged
composed and decomposed names which the inherited C++ byte lookup distinguishes.
The new regression first lost the requested edit and its history. BoneNameIdentity
now compares UTF-8 bytes, shared by command no-op decisions, edge snapshot equality
and the inspector draft. Apply eligibility uses the same exact-name predicate.
Accepted edge snapshot changes reset drafts using byte-sensitive equality.

A test-owned native field reproduced a further boundary: an atomic composed-to-
decomposed replacement did not submit through SwiftUI TextField, while the ASCII
positive control passed. The smallest bridge is ExactBoneNameField, a single
NSViewRepresentable. SwiftUI still owns the typed draft and command callbacks;
the coordinator forwards native edits/Return/Escape without maintaining a second
document state. It compares active editor text by UTF-8 and retains selection
during unrelated updates. Native system styling, placeholder and accessible
labels remain. No window registry, global control helper or QA app is involved.

Eight focused document/session/controller/native-field tests pass (3.319s),
including exact history/reopen, canonical-byte distinctions, Return submission,
Escape draft cancellation, accepted snapshot refresh and selection retention.
The native test owns an offscreen NSWindow and closes it normally. It does not
establish File-menu persistence, VoiceOver or full editor acceptance. Full
corrected-head make ci remains a separate pending gate.

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | Sources/Dust3DDocument/EdgeBoneBinding.swift; Sources/Dust3DEditor/Views/EdgeBoneBindingControls.swift; Sources/Dust3DEditor/Views/ExactBoneNameField.swift | Canonical equality could discard a byte-distinct lookup spelling and suppress native submission | Shared UTF-8 identity and a narrow native editing boundary | Preserve the actual inherited bone lookup identity across document and UI state |

## Corrected review gate

Full `make ci` on stable clean 52219442 passes 36 build-support tests and
913 XCTest cases, zero failures/reported skips (120.078s), plus formatting,
coverage, Qt-link and isolated bundle/provider checks. Six current diagnostic
images were regenerated; bound-light was inspected after the native field change.
The original SVG bytes/mtime were restored after the terminal gate.
BoneNameIdentity measures 6/6 lines and 2/2 regions; EdgeBoneBinding remains
35/35 lines and 17/17 regions. Controls measure 86/90 lines and 15/18 regions;
the native field measures 46/47 lines and 15/18 regions. Native protocol/callback
gaps remain, and Swift branch coverage was not instrumented. Whole-app File/
VoiceOver acceptance and the protected older QA state remain unchanged. The
final verification follow-up changes prose only.
