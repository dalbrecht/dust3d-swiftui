# Animation parameter addition verification (#145)

Full interface review of Add Parameter and its inline name/value form, using the
existing SwiftUI system fonts/colors, SF Symbols and native AppKit text boundary.
No supplied reference design exists and no local pixel baseline is committed.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | Actual empty/ready light, ready dark and stale light form PNGs | Names, values, instructions and actions readable at 250 points |
| Surfaces | Same forms and updated integrated dark panel | Native 40-point Add/cancel actions; inline editor retains panel conventions |
| Animations | ParameterEditor and field source | No custom motion; slowed-motion inspection inapplicable |
| Icons | Actual integrated Add Parameter plus symbol | Contextual accessible label and native symbol; clear |
| Performance | Source validation, command and no-preview store tests | Metadata addition does not regenerate static geometry; runtime timing not verified |

No actionable interface-polish findings remain in inspected states.

| Location | Candidate | Rejected because |
| --- | --- | --- |
| Existing parameter name | Replace automatically on Add | A creation action must not silently destroy retained intent; explicit Edit exists |
| Name/value form | Request initial focus for both fields | Competing attachment callbacks could steal focus from the name; value opts out |

Verification: two domain tests and three actor/store/render tests pass. They cover
existing empty/nonempty values, case sensitivity, invalid/qualified/reserved names,
missing rows, explicit empty insertion, opaque preservation, reopen, exact history,
corrected retry, original duplicate cause and stale targets after reopen/Edit-Undo.
Owned invisible windows render empty, ready light/dark and stale forms without
publishing document changes. The updated integrated dark panel was also inspected.
Full make ci passes 45 support tests and 1008 XCTest cases (122.209 seconds),
formatting, coverage gates, Qt-free linkage and isolated bundle/signature checks.

Verdict: Approve inspected static polish. Not verified: live Add activation,
Return/Escape/focus traversal in the two-field form, VoiceOver, duplicate-error
interaction, press/hover states, busy transitions and real-window resizing.
The actor/store tests prove publication rules, not native input behavior. Native
catalog/runtime acceptance and complete M6 remain open; no product app control,
production pin change or quarantine change occurs.


## Corrected-parent delivery

Preserves the actor publication-time selection fix, restored XML history
comparison and intrinsic native input minimum from accepted/validated parents.
Both parameter fields use 44-point SwiftUI layout around native controls whose
actual bounds are checked at >=40 points; action labels retain the same minimum.
All six focused parameter tests pass (0.736 seconds), covering domain duplicate
rejection without overwrite, corrected draft retry, stale epochs and exact source
preservation. Fresh ready-dark and stale-light 250-point owned offscreen renders
inspected with native styles; Add is disabled for stale targets and input retained.
No native generation/playback, protected app control or production pin change.
Fresh full `make ci` passes 45 support tests and 1,012 XCTest cases (122.458 seconds), formatting, configured coverage, Qt-link and isolated bundle checks; live keyboard/VoiceOver acceptance remains unverified.


## Native Undo/Redo correction integration

This source includes #268's observable command validation and actual UndoManager
regressions. A terminal index-write timeout interrupted preparation of its base
checkout; every changed, removed and untracked path was compared against the
saved base before repairing only index/HEAD bookkeeping and replaying existing
commits. Original branches remain preserved. Fresh full `make ci` passes 45
support tests and 1,014 XCTest cases (122.871 seconds), formatting, configured
coverage, Qt-link and isolated bundle checks. Logs/source hashes retained in the
corrected checkpoint. No native animation evaluation, production pin/quarantine
change, protected app control or manual SVG restoration. Public delivery remains
serial and requires clean exact-head automated review and every CI check green.
