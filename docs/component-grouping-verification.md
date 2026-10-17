# Native component grouping verification

Regression-first tests failed for missing multi-selection and controller APIs. Pure-state/session tests cover atomic rejection of missing identities, selection exclusivity, unchanged bytes/revision/history, single-inspector ambiguity, sibling/parent eligibility, opaque and parsed-empty group restrictions, extension-only groups, pruning deleted identities and non-revival on Undo. Controller tests cover two-part grouping/ungrouping, one publication per edit, fresh preview, unchanged camera, selected new group and exact Undo/Redo. The two-part fixture retains 32 triangles.

Full `make ci` passes 329 XCTest tests, strict native builds, formatting, coverage gates and Qt-free linkage. Measured coverage: document 2232/2316, editor model 1337/1343, pure editor state 519/519, undo 97/97 and mesh 66/67. No inherited C++ or whole-app coverage claim.

## Native evidence

Used the existing QA bundle with a disposable Capsule archive. The actions menu grouped Capsule into a new selected group while retaining the rendered 80-triangle preview. Cmd-click selected parent and child together, displayed the two-component count and removed the ambiguous single inspector; grouping, ungrouping and single-group collapse controls were disabled for that mixed-parent selection. Selecting a node cleared component selection, then selecting the group enabled Ungroup. Native Ungroup promoted Capsule and cleared the removed wrapper selection.

Saved both grouped and ungrouped states. Undo followed by settled Save matched the grouped archive byte for byte. Redo/Save matched the ungrouped archive byte for byte. Two Undo steps and Save restored the original Capsule archive exactly; the app quit normally. Inspected the rendered sidebar and preview without inventing a design baseline. Accessibility row clicks did not consistently reduce an existing multi-selection. Automated review identified this gap, and a failing regression preceded explicit Select Only… and Clear Component Selection actions. Controller tests verify singleton inspection, clearing, stale-menu identity rejection and unchanged publication/preview. Keyboard-only range navigation, VoiceOver, hidden-descendant selection and minimum-window checks remain manual acceptance gaps.

Reparent controls and modifier parity remain pending under #62. This stage does not complete M3.

The explicit selection-menu review fix passes the full automated gate. Its follow-up native check remains pending: the system Open panel exposed disabled controls, and the computer-control helper subsequently timed out reading the same QA process. The Mac lock flag was false. No crash, restart or discard was inferred from the timeout. Earlier rendered grouping and saved-history evidence above predates this menu-only fix.
