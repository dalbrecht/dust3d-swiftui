# Native component color verification

Issue #118; ADR 0059. Reference source: `dust3d/base/color.h`, component color
serialization/import and setters in `application/sources/document.cc`, and
procedural color consumers in `dust3d/mesh/mesh_generator.cc`.

## Contracts and TDD

Initial document tests failed on missing color types/commands. Source parsing
covers exact ASCII six/eight-digit notation, alpha-first order, leading zeroes,
opaque alpha equivalence, valid defaults and unsupported/named/empty/malformed
text. Commands preserve child XML/colors, unknown attributes/assets, hierarchy,
original spelling on no-ops, redo and exact undo/save/reopen. Missing components
reject atomically. Public channel construction uses UInt8 to prevent invalid state.

Controller tests first failed on missing routing. With the real cached source
preview they verify changed RGB vertex colors, opaque preview alpha, unchanged
triangle count/selection/camera, one publication per genuine edit, no regeneration
on no-ops, exact geometry/archive undo/redo and restored fallback on removal.
Invalid and stopped edits do not publish. The native color conversion tests first
failed on the missing helper; they verify sRGB eight-bit/alpha round trips and
finite bounded quantization before integer conversion, including a real native
pattern color that cannot convert to sRGB. New pure draft-state tests first failed
on the missing value, then verify failed conversion retains text/blocks Apply,
editing/choosing/reset recovery, absence versus unsupported defaults, and bounded
Unicode summaries even for a single enormous combining-character cluster.

The rendering test first failed on missing controls. It renders production controls
at the 250-point inspector width for unset, opaque, alpha, unsupported, empty and
long source states in both appearances. Rendering must preserve exact archive
bytes, empty undo history and zero publications. The test-owned window stays
hidden and activation is prohibited; no product bundle or new QA identity is used.
No reference pixel baseline is invented.

## Full gate and measured coverage

Final `make ci` passes: 533 tests, two existing no-Metal-device skips, zero failures
(81.047 seconds), formatting, native build, enforced module coverage, Qt-free
linkage and isolated signed bundle rebuild/archive checks. Measured line coverage:
color value 34/34, color XML 30/30, pure draft state 28/28, native conversion 18/18
(all 100%); SwiftUI controls 98/130 (75.38%); whole existing EditorStore 682/793
(86.00%). Native callback/error-presentation paths remain outside the instrumented
view coverage. The 95% shared UI/application target is not claimed. Nontrivial
draft logic was extracted into the pure state value rather than hiding that gap.

## Native interaction evidence

Rebuilt/ad-hoc-signed the same `/private/tmp/dust3d-combine-qa/Dust3DEditor.app`,
reusing `org.dust3d.editor.combine-qa`; verified no running editor before staging.
The disposable independent fixture has one node at (.5, .5, .5), radius .1, one
Model part/component, unsupported source color `future`, unknown canvas/part/
component attributes and asset bytes `00 FF 0A 80`.

Through native UI automation: invalid `#GG1122` produces the specific error with
Undo disabled; Escape clears the draft and retains unsupported source metadata.
Applying `#8000FF00` updates the native well and visibly renders a green 16-triangle
mesh; the opacity disclaimer remains readable in the full window. Native Save
preserves exact alpha-first color plus unknown attributes/assets. Undo/Save restores
the original archive byte-for-byte; Redo/Save reproduces the edited archive exactly.
Close/Open reopens the color and starts with clean undo history. Use Default Color
removes only the explicit attribute; Undo/Save restores exact edited bytes.
Reset Draft restores the current value without consuming redo or modifying bytes.
Quit exits with no editor process left and no unsaved document. No human button
press, new app identity or unrequested system preference change was needed.

The helper exposed only the document after native color-panel actions; actual
panel selection is not confirmed. Unit tests cover its conversion/draft boundary,
but this is not reported as a live color-panel pass.

## Limits

Alpha is saved but the native mesh/Metal preview stays opaque. Picker conversion
is not a calibrated lighting/PBR or color-management acceptance claim. Live native picker selection, a complete keyboard-only/focus/VoiceOver pass,
calibrated GPU comparisons and Qt differential acceptance remain unverified.
The limited live hex/escape/save/mesh checks above do not replace those gates. UVs, texture baking, image materials,
transparency and GLB imports remain required M4 stages. M3 acceptance and later
editor milestones are incomplete; Swift coverage does not measure inherited C++.

## Interface review

Full mode; scope is the new component-color section and its native conversion
boundary, using SwiftUI system controls/fonts/colors. Inspected twelve production
section PNGs across six states and both appearances, plus relevant view code.
Whole-app styling and the live system color panel are outside this evidence.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | Monospaced hex, short/long source text and guidance in twelve PNGs | Clear; bounded source summary wraps |
| Surfaces | Native color well, fields and action spacing | Clear; disabled/default states distinguishable |
| Animations | Static implementation; no custom transitions | Clear; no custom motion to slow down |
| Icons | Native color well only; no added icon set | Not applicable |
| Performance | Source summary reads at most 321 UTF-8 bytes; no added effects | Clear for this scope; runtime not profiled |

No actionable interface-polish findings. Considered but rejected: custom swatch
chrome (native well already conveys opacity); an invented default color attributed
to unset source (generator fallback depends on the component); animated Apply
feedback (frequent edits already have static state/error feedback). Rendering
assertions also prove zero document publication/history changes. Verdict: Approve
for inspected scope. Live color-panel selection, complete keyboard/VoiceOver acceptance, transient
conversion-error presentation and calibrated GPU comparisons remain unverified.
The native hex/Escape/save/reopen and full-window green mesh checks above pass.
