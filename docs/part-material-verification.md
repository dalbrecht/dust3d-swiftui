# Native part material parameter verification

Issue #116; ADR 0058. Reference anchors: `application/sources/document.cc`
serialization/import and material setters; `component_property_widget.cc` material
slider ranges; `uv_map_generator.cc::generateTextureMaterialImages` bake behavior.

## Contracts

Document tests first failed on missing material APIs, then pass defaults, legacy
comma decimals, finite/Float validation, unsupported and underflowing source
values, role-independent retention, exact semantic no-ops/redo, default removal,
original attributes/assets and exact undo/redo/save/reopen. Controller tests first
failed on missing routing, then pass actual core-generated preview retention,
selection/camera preservation, one publication per real change, unchanged preview
revision for no-ops, rejected drafts and stopped-store protection.

One rendering contract first failed on the missing controls. Four final production
section renders cover known/unsupported values and light/dark appearances at the
250-point inspector width, with exact source bytes and empty history assertions.
The same reference fixture enriches existing whole-inspector render coverage.
No visible window or QA app identity is created; no pixel baseline is committed.

## Full gate and coverage

`make ci` passes: 520 tests, two existing no-Metal-device skips, zero failures
(81.528 seconds). Formatting, native build, enforced module coverage, Qt-free
linkage and isolated signed bundle rebuild/archive checks pass. New material
logic is 32/32 lines (100%); material controls 97/101 (96.04%), with native action
closures left for interaction checks. Whole existing EditorStore is 664/775
(85.68%); the shared 95% application target is not claimed for the entire store.

## Limits

These parameters are editable and saved; metallic/roughness/glow are not yet
shown in the current preview. UV/texture baking, color/alpha controls, material
shading, GLB imports and full M4 acceptance remain incomplete. Native pointer,
keyboard/Escape, VoiceOver and final whole-window GPU checks remain unverified;
offscreen drawing does not prove those interactions. Swift coverage does not
measure inherited C++ code. M3 modifier/Qt differential acceptance remains open.

## Interface review

Full mode; scope is the new material section only, using SwiftUI system fonts,
semantic colors, SF-native controls and the existing inspector width. Inspected
production code and all four final section PNGs; whole-app polish is not implied.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | Known/unsupported values and wrapped guidance in both appearances | Clear; stable numeric text |
| Surfaces | Section spacing and native control surfaces in four PNGs | Clear |
| Animations | Static control implementation | Clear; no custom motion to slow down |
| Icons | No icons added in this section | Not applicable |
| Performance | No added effect/animation work in view code | Clear for this scope; runtime not profiled |

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| LOW | `Sources/Dust3DEditor/Views/PartMaterialControls.swift:40` | Proportional draft numerals in the initial implementation | Monospaced digits in drafts and numeric guidance | Stable numerals reduce visual movement during edits |
| MEDIUM | `Sources/Dust3DEditor/Views/PartMaterialControls.swift:53` and `:56` | Minimum frame outside the button label | Minimum height inside each action label | Expand the actual button content rather than only surrounding layout |

Considered but rejected: custom warning colors (unsupported metadata is preserved,
not a destructive error); animated Apply feedback (frequent edits already have
static state/error feedback); custom control chrome (would conflict with the
native inspector). No actionable visual findings remain in inspected section
renders. Verdict: Approve for this scope; live keyboard, pointer hit areas,
VoiceOver and whole-window layout remain unverified.
