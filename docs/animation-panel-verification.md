# Stored-animation panel verification (#145)

Full interface review: SwiftUI inspector, List and native AppKit name field.
System fonts, semantic colors, SF Symbols and native button/list styles are used.
Scope is the panel and command policies; the entire running app was not inspected.
No supplied reference design exists and no local pixel baseline is committed.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | Actual 250-point light/dark selected, empty, unavailable, long-name/type and current/stale rename PNGs | Clipped actions corrected; long records truncate in rows and wrap in details |
| Surfaces | Same renders; panel padding and renderer padding; native controls | Double test inset corrected; no custom row cards |
| Animations | Panel source and state transitions | No custom/high-frequency motion introduced; slowed motion inspection inapplicable |
| Icons | Actual film, refresh, warning and trash symbols in light/dark | Semantic symbols and accessible action labels; clear |
| Performance | Explicit source refresh, query guards and lazy parameter rows | No native generation in six panel tests; large-document runtime timing not verified |

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| Medium | Sources/Dust3DEditor/Views/AnimationPanel.swift:119 | Three action labels clipped at narrow width | Two equal-width actions plus full-width Delete | Readable actions with native 40-point hit regions |
| High | Sources/Dust3DEditor/Views/AnimationPanel.swift:31 | Unavailable catalog displayed zero | Count requires successful current catalog | Failed optional metadata must not imply empty data |
| Medium | Sources/Dust3DEditor/Views/AnimationPanel.swift:65 | Name editing retained inactive actions and a select prompt | Draft shows its own actions and stale-source explanation | Avoid competing instructions while retaining input |
| Low | Tests/Dust3DEditorTests/Support/InspectorRenderer.swift:1 | Helper and panel both supplied insets | Optional bounded helper padding; panel render uses zero | Inspect actual production width while retaining other callers' defaults |

Considered but rejected:

| Location | Candidate | Rejected because |
| --- | --- | --- |
| AnimationPanel list | Custom cards, borders and shadow for each row | Native selection already supplies hierarchy and state |
| AnimationPanel actions | Decorative transitions on selection and typing | Repeated motion distracts from document editing; native feedback suffices |

Verification: six AnimationPanelTests pass, including exact UTF-8 text, Return/
Escape intent, rejected/accepted publication, command scope and native-vs-document
undo routing. Existing InspectorRenderer owns an invisible window, prohibits
activation, checks invisibility and closes only that window. Renders retain
archive bytes/history and cause no document publication. Ten PNGs were inspected
locally; these are offscreen panel previews, not live app screenshots. Initial
missing-API compile failure and pre-fix PNGs are retained in the ignored checkpoint.
Full make ci passes: 45 build-support tests, 998 XCTest cases (121.028 seconds),
formatting, existing coverage gates, Qt-free linkage and isolated packaging.

Verdict: Approve the inspected panel polish. Not verified: live app keyboard/menu
validation, native first-responder traversal, VoiceOver, hover/press behavior,
loading transitions, duplicate-form interaction, resizing in a live window and
large-document runtime performance. Those remain explicit acceptance tasks; the
owned test controls do not establish them. Creation/type/parameter controls,
native runtime/catalog acceptance, playback and audio remain open in M6.


## Corrected-parent delivery and hit-area regression

Rebased onto the store stage containing #266's selection-publication fix. Fresh
focused `AnimationPanelTests` passes all six methods, including a new inspection
of the actual native field in both current and stale owned offscreen draft windows.
The regression first measured 24-point bounds and failed twice; a larger SwiftUI
frame alone retained those bounds. The field now declares a minimum 40-point
intrinsic height, and draft buttons size their labels rather than outer containers.
All six tests then pass (1.617 seconds), preserving exact document bytes.

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| Medium | AnimationNameField.InitialFocusField; AnimationPanel.nameEditor | Native input bounds 24 points; draft action frame outside button | Native input intrinsic minimum 40; action labels minimum 40 | Actual desktop hit areas, not just surrounding layout, must be usable |

Fresh current-draft light and selected dark PNGs inspected after correction;
native typography, semantic surfaces and SF Symbols retained. No new motion or
dependency. Fresh full `make ci` passes 45 support tests and 1,002 XCTest cases (121.763 seconds), formatting, configured coverage, Qt-link and isolated build-only bundle checks for this corrected UI source. Live app interaction,
VoiceOver and native first-responder traversal remain unverified as above; the
rendered/native bounds check does not establish those acceptance requirements.


## Review correction: native Undo/Redo availability

PR #268 finding4369432594 identified that AppKit text editors and UndoManager
are not observable SwiftUI values, so command enablement could remain stale. A
main-actor observable bridge now refreshes command validation for undo-group close,
undo/redo, native text editing/selection and key-window changes, delivered through
the main run loop. The app reads that revision when resolving its native editor.
Checkpoint notifications are deliberately excluded: querying canRedo itself emits
a checkpoint and must not create a validation feedback loop.

The missing-observer regression first failed to compile, then both focused tests
pass (0.138 seconds): all subscribed notifications refresh the revision, and an
actual UndoManager registration/undo/redo cycle invalidates Observation tracking
while preserving stable revision on a later canRedo query. These tests control
no product app/window. Full local gate and new exact-head review remain required;
this does not replace live keyboard/menu/VoiceOver acceptance.

Fresh full `make ci` passes 45 support tests and 1,004 XCTest cases (123.704
seconds), formatting, configured coverage, Qt-link and isolated bundle checks.
NativeUndoCommandState measures 21/21 lines and 5/5 regions; Swift reports no
branch outcomes. Red/green/full logs, coverage and tested source hashes retained
in the review-fix checkpoint. Require completed clean review and all CI on the
new head before merge. No native animation evaluation or protected app control.
