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

## Final implementation gate and rendered inspection

Commit e97ff9aa passed the full local gate: 36 support checks and 919 XCTest tests,
zero failures (121.245 seconds), plus formatting, scoped coverage, Qt-link and
isolated packaging/provider checks. No live QA bundle was overwritten.

An additional offscreen render test then passed in 1.147 seconds. It exports six
632×432 captures (light/dark × before/preview/cancelled), verifies projected preview
and cancellation state, and checks unchanged archive/history. Captures are retained
in the reboot checkpoint, not committed as environment-specific baselines. This
uses the existing test-owned renderer and does not activate a product window.

Full interface-polish review scope: node cancellation states only; SwiftUI semantic
colors and existing canvas styling. No actionable interface-polish findings within
that scope.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | Six captures, existing Origin label | Clear; no new text layout |
| Surfaces | Node, edge and origin in all six captures | Clear; cancellation restores positions without residual preview |
| Animations | Gesture and cancellation source | Clear; immediate preview/cancel, no custom animation to slow down |
| Icons | Origin marker and node selection stroke | Clear; existing semantic selection treatment retained |
| Performance | Cancellation identity scoped to inner hit surface | No new broad view identity reset; runtime profiling not verified |

Considered but rejected:

| Location | Candidate | Rejected because |
| --- | --- | --- |
| NodeCanvas interaction surface | Animate cancellation | Immediate reset gives precise modelling feedback without repeated motion |
| Canvas commands | Add a permanent Cancel button | Existing Escape and Canvas menu provide the command without extra canvas chrome |
| Node handles | Enlarge hit circles during cancellation work | Dense graph hit overlap needs a separate selection policy; this stage preserves existing targets |

Verification: `make ci` at e97ff9aa passed as above;
`./script/swift.sh test --filter NodeDragRenderingTests` passed. All six exported
states were visually inspected. Scoped verdict: Approve with physical held-drag,
hover/focus interaction, VoiceOver, oldest macOS and runtime performance not
verified. This is not overall M2 acceptance. The final full gate including the render test passed at 837f104f: 36 support
checks and 920 XCTest tests, zero failures (121.105 seconds), formatting, coverage,
Qt-link and isolated packaging/provider checks. The final documentation-only
commit leaves implementation and tests unchanged.
