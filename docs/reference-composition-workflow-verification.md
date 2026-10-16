# Reference composition workflow verification

Full `make ci` passes 282 XCTest tests, formatting, strict native builds, coverage thresholds and Qt-free linkage. Swift line counts: mesh 66/67; document 1909/1986; editor model 1198/1204; pure editor state 461/461; undo 97/97. New projection is 28/28 lines, target 5/5 and composition service 11/11 (100%). Draft controller is 160/167 lines (95.81%), with 83/100 regions; native-boundary/error/guard paths remain unexercised. These reports do not measure inherited C++ or prove all app/view coverage.

TDD missing-API failures preceded atomic commit, transient draft/controller, projection and presentation implementations. A 1×5 rounding regression belongs to the foundation record. Additional missing-API regressions protect field resets and active-gesture Apply availability. Twelve tests were added to the 270-test foundation baseline:

- Image/optional origin form one lossless undo/redo transaction. Native axis locks apply; node geometry/selection remain unchanged. Invalid PNG/origin batches fail atomically, image-only changes retain origin, and identical output preserves redo.
- Document identity, monotonic revision and constraint epochs reject another window, reopened identical bytes, edits followed by Undo and lock on/off cycles. Unloaded sessions reject before editing.
- Draft import, crop, mirror and swap; invalid input removes the applicable result; explicit source/full-image reset clears field state; stale pointer completion cannot replace a newer crop. Active gestures disable Apply independently of preview readiness.
- Controlled actors prove late import after Stop and obsolete preview after a newer request cannot publish. Failed import retains prior sources and surfaces its original read diagnostic. Drafts have no document writer.
- Pure aspect-fit mapping verifies letterboxing, reversed/clamped selection, huge finite pointer coordinates, invalid/zero viewports, nonfinite points and empty selection.
- Controller completion, reference preview, one document-change notification, exact Undo, redo preservation after stale Apply, and stopped-window rejection.
- Nonoptional presentation target/identity, plus a real actor import→composition→PNG decode test using a disposable synthetic image.

## Native evidence and outstanding checks

Used the existing QA app path/bundle identity and a disposable Capsule copy. The first native presentation exposed an empty sheet; after replacing separate target/visibility state with item-based presentation, the first sheet displayed controls. Imported synthetic Front 8×4 and Side 4×8 PNGs. Numeric Front crop became (2,0,4,4). Invalid Side width disabled Apply and displayed the typed crop diagnostic. Mirror Side restored valid numeric fields and preview; swapping preserved each image/crop/mirror state. Inspected both source rectangles and the composed image.

Physical drag from (420,400) to (500,550) on the displayed mirrored Front selected (1,2,2,3) in its 4×8 pixel space, matching projection rounding. Cancel returned to the unchanged 80-triangle model with Undo disabled. Save compared byte-identical to the source fixture.

Those interactions preceded the final persistent-label, scroll-container and active-gesture UI refinements. The final app was built and launched with the same identity, but the computer-use native pipe closed when opening the sheet. Rechecking the same handle and reconnecting the controller did not restore app control; no new Dust3DEditor crash report appeared. Final-build rendered inspection, native Apply/save/Undo/Redo, flattened-existing-image reuse, held-drag Escape and broader keyboard/VoiceOver acceptance remain pending. The actor/model/controller tests cover Apply semantics but do not substitute for these native checks. No local pixel baseline was invented. Actual Qt GUI differential acceptance is also pending. See [ADR 0029](adr/0029-reference-composition-workflow.md); keep #56 open.
