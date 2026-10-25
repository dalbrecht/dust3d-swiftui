# Stored animation record creation verification (#145)

Full interface review of New Animation and its inline creation form. SwiftUI
uses system typography, semantic colors, native buttons and SF Symbols; exact
input uses the established narrow AppKit boundary. No supplied design reference
or locally committed pixel baseline exists.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | Actual empty-type, ready light/dark and stale light creation PNGs | Name/type labels, instructions, actions and stale explanation readable at 250 points |
| Surfaces | Same forms; integrated empty/light and selected/dark panel PNGs | Full-width creation affordance and 40-point native actions retain panel conventions |
| Animations | CreationEditor and panel source | No custom motion; slowed-motion inspection inapplicable |
| Icons | New Animation plus in actual integrated renders | Native symbol and contextual accessible label; clear |
| Performance | Captured-target actor/store code and no-preview tests | No static geometry regeneration from metadata creation; large-document runtime timing not verified |

No actionable interface-polish findings remain in inspected states.

| Location | Candidate | Rejected because |
| --- | --- | --- |
| Type field | Guessed catalog choices and automatic generator defaults | Runtime catalog acceptance is unavailable; retained text must not imply supported playback |
| Inspector header | Another icon-only creation button beside refresh/count | The fixed-width header is narrow; a labeled full-width action is readable and discoverable |

Verification: six actor/store/render tests pass, covering fresh selected UUIDs,
brace-wrapped identity format, preserved opaque XML, exact history/save/reopen,
reopen/Edit-Undo retirement, ambiguous/unloaded rejection, original validation
cause with retry, exact UTF-8 name, failed-Open retained-state isolation and
geometry-independent creation. Four owned creation-form states and two integrated
panel states were inspected. Invisible render windows never activate/control
product apps. Full make ci passes 45 support tests and 1014 XCTest cases
(122.573 seconds), formatting, coverage gates, Qt-free linkage and isolated
packaging/signature checks. Scoped target coverage is 9/9 lines; EditorSession
342/342. Native interaction coverage is not implied.

Verdict: Approve inspected static polish. Not verified: live New Animation action,
Return/Escape and two-field focus traversal, VoiceOver, interactive invalid-type
retention, press/hover behavior, busy transitions and real-window resizing.
Catalog-guided controls, Qt/native interoperability, native evaluation/playback/
audio and complete M6 remain open. Production pin and all quarantines are unchanged.


## Corrected-parent delivery

The record form now inherits the corrected selection publication, exact history
comparison and observable native Undo/Redo validation. Both native inputs retain
the >=40-point intrinsic hit size, 44-point layout, and input-specific accessible
identifiers; action labels retain desktop minimums. All six creation target/form
tests pass (0.734 seconds), including failed-open preservation, rejected input
retry with exact UTF-8 and stale captured epoch rejection without generation.
Fresh ready-dark and stale-light owned 250-point renders inspected: source
changes retain draft text and disable Create. No catalog defaults or supported
playback types are inferred from a stored string. Fresh full `make ci` passes 45 support tests and 1,020 XCTest cases (123.598 seconds), formatting, configured coverage, Qt-link and isolated bundle checks; live app
keyboard/VoiceOver acceptance remains unverified. No native evaluation or
production pin/quarantine changes.
