# Animation authoring UI verification (#283)

Review mode: full. Scope: new catalog availability, creation, type and parameter
controls in the native 250-point inspector. Framework/style: SwiftUI system
controls, semantic colors, SF Symbols, with the existing exact-text AppKit name
field. No redesign or additional styling dependency.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | Actual light/dark creation, long name/type, unsupported type, raw numeric/legacy values, long control labels and stale/error text | Exact values retained; labels wrap and type help exposes the full retained choice |
| Surfaces | Actual 250-point controls; source minimum label areas inside buttons; inline defaults and Apply/Cancel | Clear after label sizing; live hit testing unverified |
| Animations | No custom transitions; source/static system progress state alongside explicit loading text | Clear source/static inspection; native progress timing unverified |
| Icons | Existing SF Symbols and system control states | Clear in inspected samples |
| Performance | One optional catalog query/cache, off-main copy, pure draft projection and no evaluation in view callbacks | Clear source/injected tests; live latency/GPU unverified |

Resolved review changes:

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| LOW | `Sources/Dust3DEditor/Views/AnimationAuthoringControls.swift:18` | Outer layout frames around small labels | Minimum areas inside Cancel/Apply/Type/Parameter/Default labels | Minimum hit-area principle: enlarge the control content consistently |
| LOW | `Sources/Dust3DEditor/Views/AnimationAuthoringControls.swift:136` | Native popup truncates long type names | Exact byte tag and full type help text retained | Typography: keep long choices identifiable without widening the inspector |
| MEDIUM | `Sources/Dust3DEditor/App/EditorAnimationAuthoringWorkflow.swift:70` | Existing message asked creation users to select an animation again | Cancel and start the draft again | Recovery feedback must apply to creation as well as existing-record drafts |
| LOW | `Sources/Dust3DEditor/Views/AnimationAuthoringControls.swift:80` | Developer sampling-acceptance caveat inside controls | Keep acceptance limits in ADR; retain the panel's playback-unavailable statement | Product copy should explain user actions rather than test implementation limits |

No actionable interface-polish findings remain in the inspected scope.

## Considered but rejected

| Location | Candidate | Rejected because |
| --- | --- | --- |
| Native buttons | Force an accent color in offscreen captures | Hidden windows can dim native controls; overriding system state would misrepresent the active app |
| Draft forms | Modal parameter sheets | Inline drafts provide owned Escape/Cancel and avoid an unnecessary window/panel lifecycle |
| Controls | Animate every value change | Repeated motion adds distraction; exact text and standard controls provide static feedback |

## Verification

`InspectorRenderer.png` renders actual `AnimationAuthoringControls` in a hidden,
test-owned window that is never ordered visible; the test process has prohibited
activation policy. It does not launch/control protected QA apps. Fake catalog and
preview services supply ready/loading/error, creation, long name/type, unsupported
type, normal/unsupported parameters and stale-source states in light/dark appearance.
Rendering asserts valid PNG output, unchanged source bytes and zero publications.
Images are exported only when `DUST3D_UI_QA_OUTPUT_DIR` is supplied, under the shared
build root. They are samples rather than native generated-animation screenshots.
No local baseline is committed or claimed as a CI pixel comparison.

Focused workflow/store/model tests exercise Apply/Cancel, duplicate submission,
source epochs, optional-catalog failure, exact transactions, no-op/Redo, metadata
ownership and retained errors. Offscreen images do not verify live native menu
selection, Return/Escape/Command-Return dispatch, multi-window focus, VoiceOver,
hover tooltips, hit testing, GPU or animation/audio playback. Hidden-window button
color is not proof of an active application's appearance. Those checks remain
release acceptance work, with all feature quarantines unchanged.

Verdict: Approve for inspected source/offscreen scope. The live interactions above
remain unverified; this does not establish full M6 or editor parity.
