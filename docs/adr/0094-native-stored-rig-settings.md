# ADR 0094: Native controls for stored rig settings

Status: Implemented locally for #254 on the merged #246 foundation; historical full gate passed on 2900229b. Rebased delivery validation and native interaction acceptance remain pending.

## Decision

Expose the actor-prepared `DocumentRigSettings` snapshot in a compact, initially
collapsed Rig settings inspector section. Use the inherited template names and
head-bone eyelid flag. Each explicit choice is one undoable document command;
semantic no-ops retain exact source bytes and history. An unsupported template has
an explicit disabled placeholder and remains untouched until a known replacement
is chosen. The UI never displays an unbounded raw source attribute.

The controller rejects unloaded, busy and stopped edits. A new optional
`changesRendering` flag on the existing serialized operation path defaults true;
only these two stored-intent setters opt out. Accepted snapshots and document
publication still advance normally, while direct settings edits leave ordinary
geometry, material state, camera and selection unchanged. Existing general
Undo/Redo continues its ordinary preview-refresh behavior. No skeleton, weights,
animation or pose evaluator is added or invoked by these controls. The UI states
that settings take effect on save and that skeleton/pose preview is unavailable.

Keep the reference Qt `BonePropertyWidget` eyelid meaning and the template names
documented in ADR 0091. Preserve unsupported fields/assets. No core pin, C ABI,
license or dependency change. This does not release Apple #199 or complete M5.

## Verification

The new store/control tests first failed to compile against the missing APIs.
Three focused contracts now pass: exact archive/history and reopen behavior with
unknown metadata and an opaque asset; busy/no-op/stop/selection/lock/window
isolation; and sixteen collapsed/expanded light/dark renders across unloaded,
unsupported, recognized and stopped states without mutating the document.
A counting ordinary preview service verifies that direct changes do not enqueue
additional geometry evaluation. These are controller and scoped render tests, not
native File menu, popup keyboard or full application acceptance.

Before delivery rebasing, full `make ci` on 2900229b passed 36 build-support tests and 904 XCTest cases
(zero failures or reported skips; 115.875s), formatting, existing coverage
thresholds, Qt-link checks and isolated bundle/provider checks. Compiler-attributed
control coverage is 171/173 lines and 23/26 regions; the native binding callbacks
are not exercised by these scoped renders. Swift branch coverage was not
instrumented. These figures do not establish native control or inherited-engine
coverage. Six representative current-state PNGs, including collapsed, unsupported,
checked and stopped controls, were visually inspected.

The current running older QA bundle is preserved. Native control, keyboard focus,
VoiceOver and save/reopen acceptance on a safely launched future build remain open.
No further control-helper timeout probes or forced quit are used. No screenshot
baseline is introduced; PNGs are diagnostic artifacts in the shared build root.

## Interface review (full scope)

Scope: Rig settings disclosure, template picker, eyelid checkbox, unsupported and
unavailable states. SwiftUI uses the existing semantic system colors, native
controls and headline/caption hierarchy. This review does not cover a generated
skeleton, animation UI or the rest of the editor.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | 250-point inspector renders; bounded summary and wrapped notices | Clear; unsupported labels fit, no raw unbounded template string |
| Surfaces | Native disclosure/picker/toggle and light/dark diagnostic renders | Clear; existing flat inspector styling, no new background system |
| Animations | Control source and operation flow | None added; ordinary feedback remains immediate |
| Icons | System disclosure and checkbox affordances | Native symbols retained; no new icon assets |
| Performance | Cached snapshot reads and counting preview service | No per-view XML parse or direct settings-triggered preview work |

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | Sources/Dust3DEditor/Views/RigSettingsControls.swift:15 | Stored rig settings had no native inspector | Collapsed native section with template summary and accessible controls | Keep document-wide options discoverable without crowding node editing |
| MEDIUM | Sources/Dust3DEditor/Views/RigSettingsControls.swift:26 | No native representation for unsupported intent | Explicit Unsupported template entry and retention notice | Make the saved intent visible without silently replacing it |
| MEDIUM | Sources/Dust3DEditor/Views/RigSettingsControls.swift:54 | No native capability explanation beside these settings | Explicit save and unavailable-preview notice | Avoid implying that a stored setting generates a native skeleton |

| Location | Considered candidate | Rejected because |
| --- | --- | --- |
| Rig settings section | Always-expanded custom card | It adds bulk above the existing selection controls and conflicts with the flat inspector |
| Template changes | Automatically generate or animate a skeleton | Native evaluation remains quarantined/unavailable; saving intent must not imply preview support |
| Unsupported template | Display the entire original attribute | Unbounded source text is unsuitable for a narrow inspector; exact data remains in the archive |

Verdict: Approve the inspected static presentation and tested controller behavior;
native interactions, keyboard focus, VoiceOver and native save acceptance are not
verified. No actionable static polish findings remain. Full local validation and
automated PR review remain separate gates.
