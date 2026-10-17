# Native component reparent verification

Regression-first model/session/controller tests failed for missing parent-choice and reparent APIs. Tests cover root/group choices, source/descendant/current-parent exclusion, unsupported link destinations, name/identity filtering, missing sources, explicit root encoding, changed document/window/revision/selection targets, Undo invalidation, rejected cycles/missing destinations, atomic history, retained subtree selection and preview/publication behavior. The two-part controller fixture retains 32 triangles and exact Undo/Redo bytes without a camera reset.

Full `make ci` passes 333 XCTest tests, strict builds, formatting, coverage gates and Qt-free linkage. Measured coverage: document 2232/2316, editor model 1394/1400, pure editor state 523/523, undo 97/97 and mesh 66/67. No inherited C++ or whole-app coverage claim.

## Native evidence

Used the existing QA bundle and disposable nested Capsule hierarchy. The inline chooser listed Document Root and Empty group, excluded the current Assembly parent and source, filtered to Empty group and enabled Move only after selection. A temporary rename invalidated the draft, disabled Move and displayed Reset guidance. Reset cleared query/selection, Cancel closed without a structural edit, and Undo restored the temporary rename.

Move transferred Capsule from Assembly to Empty group, retained selection and the rendered 80-triangle preview. Independent saved XML inspection found an empty Assembly, Capsule nested under Empty group, and the same three nodes/two edges. Undo/Save restored the baseline archive byte for byte; Redo/Save matched the applied archive byte for byte. A final Undo/Save restored the disposable fixture exactly and the app quit normally.

Rendered inspection caught a clipped Cancel label and stale native accessibility parent text: pixels showed the new parent while the full accessibility tree retained the old value. The label was shortened and the selectable parent text now changes view identity with the parent. A fresh native two-part document verified that moving between groups updates the AX parent UUID; the full automated gate passes. Switching component selection exposed the same caching behavior in the component-ID text, which now also changes view identity with its value. Reopening the saved two-part fixture and selecting both component rows verified distinct correct AX UUIDs, and final rendered inspection verified that Cancel/Reset/Move fit the inspector. These are thin native text boundaries, and manual regressions are retained explicitly rather than claiming pure model tests cover framework accessibility caching.

Keyboard-only list traversal, VoiceOver, deep/minimum-window layouts and Qt modifier differential acceptance remain pending under #62. This stage does not complete M3.

The background-launched QA app exposed inactive Open/Save controls despite an unlocked console. Reading its process activation metadata showed it was not frontmost. Finder navigation to the QA bundle and its advertised native open action brought the same existing app forward and enabled the Save controls. The new two-part accessibility fixture was saved to a temporary archive without discarding its document; the Editor placeholder icon was also inspected in the standard About panel. No Dock restart or default association change was needed.

The reopened native two-part fixture reports 32 triangles but its viewport remained visually blank after Fit. That is tracked in #73 for the next rendering investigation; this report does not equate a triangle-count caption or CPU/controller mesh check with successful GPU rendering. The colored Capsule rendering/history evidence above remains separate.
