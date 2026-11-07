# ADR 0175: Global canvas part visibility

Status: Activated Qt modeling parity follow-up, Apple #343.

Qt's SkeletonGraphicsWidget::shortcutShowOrHideSelectedPart at 2188–2201 calls
showOrHideAllComponents when there is no last checked part. DocumentWindow connects
that signal at 787. Document::showOrHideAllComponents at 1307–1318 hides every part
when any is visible, otherwise restoring visibility. Native part and isolation
controls already supplied restoration, but did not expose global Hide All.
Unused lock-all/lock-others/descendant-state helpers are not treated as UI features.

Add CanvasPartIsolationTarget.hidingAll(in:) as a pure global visibility plan.
Capture all part IDs in source order if any is visible; otherwise return an
unavailable no-op with an accurate all-hidden reason. Component membership is
irrelevant, so malformed hierarchy interpretation does not block global recovery.
Orphan, hidden, locked and disabled parts remain in scope. Only the visible flag
changes; locked/disabled flags, opaque data and geometry/material identities stay
unchanged. Existing actor/store transaction, cancellation, stale-epoch admission
and Undo/Redo handle publication without a duplicate command implementation.

Group Hide All, Hide Other Parts and Show All under Canvas > Part Visibility.
Part/component inspector isolation remains tied to its rendered scope. Hide All
is a global operation; Show All restores canvas visibility with no selection.
Native keyboard access uses the menu path; this change does not install Qt's plain
H as an app-wide text binding. Main-menu unavailable commands remain discoverable.

TDD pure tests cover global source order, broken component metadata, orphan and
read-only flags, no-op/empty models, bulk scope and source/selection/constraint ABA.
Copied-data store tests verify one publication, exact Undo/Redo, restoration and
unchanged preview-generation calls. No new native generation, GUI, NSView/NSEvent,
Metal-device or fault probes are added. Physical menu, keyboard/VoiceOver and
broader modeling acceptance remain outstanding. This does not establish full
Qt/HIG parity; production pin and runtime quarantines are unchanged.
