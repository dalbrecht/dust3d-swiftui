# Node drag verification

This change addresses stale node-canvas gestures under #245. A drag captures the
document identity and revision, selection generation, locks and fixed projection.
The session validates the capture before moving the anchor or selected group as
one edit. Selection changes advance a transient generation even if the original
selection is restored; repeating the same selection is a no-op. Gesture preview
and reset remain per-window and do not write the archive.

The regression for a selection cycle first failed: the old gesture committed and
created undo history after selection returned to its original value. The updated
tests cover that case, exclusive selection transitions, redundant selections,
cross-window and replaced documents, intervening edits and lock cycles, invalid
coordinates, group movement and exact undo. Independent review found that a late
callback could consume or reset a newer gesture. The follow-up uses a small AppKit
pointer view that generates an identity at mouse-down and carries it through
updates, completion and cancellation. Lifecycle tests cover stale callbacks for
different and repeated anchors. Synthetic events exercise click, Command-click,
drag, Escape, responder refusal, window resignation, removal and hit testing.
The full canvas uses the captured projection while a drag is active; a controlled
delayed reference-image test covers a fit changing the fallback projection.
These tests do not establish physical event delivery.

The preceding candidate (commit `28718b07`) passed `make ci` outside the command sandbox on October
30, 2026: 1,111 XCTest cases and 45 build-support tests passed, with no reported
XCTest skips. The gate also passed formatting, Qt-free linkage and isolated signed
bundle rebuild checks. Line coverage was 3185/3229 for the Swift mesh library,
4018/4114 for documents, 2127/2148 for the editor model, 570/570 for pure editor
state, 121/121 for undo and 33/33 for orbit camera. These figures do not measure
the inherited C++ engine or prove GPU behavior. These results precede the AppKit
pointer follow-up.

The reviewed pointer follow-up passed `make ci` on October 30, 2026: 1,121
XCTest cases and 45 build-support tests passed, along with formatting, Qt-free
linkage and the isolated bundle rebuild. Coverage was 3185/3229 mesh library,
4018/4114 documents, 2138/2153 editor model, 570/570 pure editor state, 121/121
undo and 33/33 orbit camera. Physical pointer and VoiceOver acceptance remain open.

A hosted-canvas test resolves the actual node pointer hit target and invokes
synthetic events directly on that view, checking the resulting store edit. An
attempt to dispatch events through an owned offscreen `NSWindow.sendEvent` did
not move the node; active-app and first-mouse preconditions were not established.
That test process also exited with signal 11 during cleanup. The probe omitted
the project's `isReleasedWhenClosed = false` lifetime guard; the cause of the
crash remains unproven. Neither result establishes a product defect or successful
window-server routing. The direct-hit test does not replace that missing evidence.

An earlier version of this candidate, before the selection-generation addition,
was launched as a separate QA process on a disposable Capsule copy. One physical
Front drag changed Node 1 X from 0.5 to 0.5575239923224569. Undo/Save restored
the original archive byte-for-byte and Redo/Save restored the edited archive hash.
Subsequent Side and Front drag attempts produced no observed movement while the
QA window appeared inactive; the observations do not distinguish input focus
from a product regression. The later selection-generation change was not tested
in that process. Repeated and Side drags, cancellation during a held gesture,
VoiceOver, and current-candidate native behavior remain unverified. The original
fixture was not modified.
