# Stored animation value controls verification (#145)

Full interface review, scoped to the retained-type/existing-parameter edit forms
and integrated animation panel. SwiftUI uses semantic system colors/fonts, native
buttons and SF Symbols, with the existing narrow AppKit text-field boundary. No
supplied reference design or committed pixel baseline exists.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | Actual type and parameter light/dark form PNGs; integrated selected/light and long-type/dark panel PNGs | Instructions, actions and values readable at 250 points |
| Surfaces | Same forms and integrated panel | Existing inline spacing, native fields/buttons and 40-point edit hit regions retained |
| Animations | AnimationValueEditor and AnimationPanel source | No custom motion; slowed-motion inspection inapplicable |
| Icons | Pencil affordances and Remove Parameter trash in actual renders | Semantic SF Symbols and contextual accessibility labels |
| Performance | Source-bound draft, actor/store workflow and no-preview test substitute | No geometry regeneration for metadata edits; large-document runtime performance not verified |

No actionable interface-polish findings remain in the inspected states.

| Location | Candidate | Rejected because |
| --- | --- | --- |
| Stored type | An inferred type picker | Runtime catalog acceptance is unavailable; guessing choices would misrepresent support |
| Parameter value | Numeric sliders and automatic default conversion | Unknown parameters retain opaque text and may use unsupported units; conversion would lose intent |

Verification: five AnimationValueDraftTests pass. They exercise exact field/name
mapping, 128/129-byte name boundary, reserved/qualified names, empty versus removal,
rejected type input, replaced-document stale target, save/reopen, exact undo/redo,
opaque namespace/child preservation and unchanged preview revision. The existing
native text-field tests cover Return/Escape intent. Four new form PNGs and two
updated integrated panel PNGs were inspected. Owned offscreen render windows are
invisible and never activate or control product apps. The full make ci passes
45 support tests and 1003 XCTest cases (121.793 seconds), formatting, coverage
gates, Qt-free linkage and isolated bundle/signature checks. Scoped line coverage:
DocumentAnimation.swift 50/50; AnimationStoredField.swift 24/25. No whole-shell
coverage or runtime parity claim follows from those numbers.

Verdict: Approve the inspected static interface polish. Not verified: live pencil
activation, keyboard traversal/menu validation, VoiceOver, press/hover behavior,
stale/busy form rendering, interactive rejection retention and real-window
resizing. Store tests establish rejected/stale publication behavior, not those
native UI interactions. Creation, parameter addition, catalog-specific controls,
native evaluation/playback/audio and complete M6 acceptance remain open.


## Corrected-parent delivery

Replayed onto the inspector with #266's publication-time selection pruning and
its history regression. Existing XML equality and exact-byte restoration fixes
remain intact. Forms retain the inspector's minimum 40-point native input height
and size action labels rather than surrounding containers. The owned render test
checks actual native stored-value input bounds in light and dark modes. All five
AnimationValueDraftTests pass (0.841 seconds), including exact UTF-8, qualified
attribute restrictions, empty/removal semantics, stale-source rejection and
lossless save/reopen/history without native evaluation. Fresh type-light and
parameter-dark PNGs inspected at 250 points; system styles retained. Fresh full `make ci` passes 45 support tests and 1,007 XCTest cases
(121.945 seconds), formatting, configured coverage, Qt-link and isolated
build-only bundle checks. Live app keyboard/VoiceOver acceptance remains unverified.


## Incorporate native Undo/Redo review correction

The stored-value stage includes #268's notification-backed native command
validation and both ordinary UndoManager/Observation regressions. Compared with
the earlier gated stage, source changes are limited to the app's revision read
and the new observer/tests; stored-value behavior and prior exact-history fixes
remain intact. Fresh full `make ci` passes 45 support tests and 1,009 XCTest
cases (123.864 seconds), formatting, configured coverage, Qt-link and isolated
bundle checks. Logs and all runtime/test/manifest hashes are retained in the
corrected checkpoint. Known ordinary pinned-fixture SVG writes remain untouched.
No native animation evaluation, production dependency change or protected app
control. Parent acceptance, clean exact-head review and all green CI remain
required before merge; live keyboard/menu/VoiceOver acceptance remains open.
