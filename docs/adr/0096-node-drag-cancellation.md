# ADR 0096: Cancellable node movement baselines

Status: Implemented locally; native pointer acceptance pending.

## Decision

Capture an immutable node gesture baseline with document identity, document and
constraint revisions, selected node/edge identities, axis locks and projection.
Commit through the serial editing actor after revalidating that baseline. Preserve
existing editable-group movement and the exact archive undo transaction.

The window store owns transient preview state and a recognizer generation. Escape,
context changes and commands invalidate that generation. Old update/end callbacks
are ignored; only a fresh recognizer may start another movement. Reset the inner
interaction surface while retaining the outer node accessibility element. The
Canvas menu exposes Cancel Canvas Move for node previews and origin mode.

This prevents a cancelled gesture callback from committing later and keeps preview
out of the document/history. No dependency or production core pin changes.

## Evidence and limits

Eleven initial focused node/origin model and store tests passed; the final six
node-only tests also cover unselected anchors and read-only nodes. Tests began red for missing
baseline/commit and cancellation APIs. They cover unchanged preview bytes/history,
late callback rejection, fresh movement, exact undo/redo, fixed projection, groups,
axis locks, replacement, changed selection, lock epochs and window identity.

Two private AppKit pointer positive controls failed to exercise a SwiftUI drag.
They are retained outside the test target with logs in the reboot checkpoint.
These failures do not establish a product pointer defect or physical held-Escape
acceptance. No global input escalation was used. Native held gesture, VoiceOver,
Qt reopen and full M2 acceptance remain open under #245. The potentially unsaved
older QA application was not touched. The initial full local gate passed 36 support checks and 918 XCTest tests
(121.377 seconds), including formatting, coverage and isolated packaging/provider
checks. Additional coverage-driven cases then passed in the six node-only tests.
The new baseline measures 32/32 lines and 18/18 regions; Swift branch outcomes
are not instrumented. A final full gate follows those additional tests. No
whole-core coverage or native pointer acceptance claim is made.
