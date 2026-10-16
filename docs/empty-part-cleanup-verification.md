# Empty-part cleanup verification

Full `make ci` passes 243 XCTest tests, strict formatting, native builds, coverage and Qt-free linkage for both apps. Swift coverage: mesh 66/67; document 1894/1971; editor model 963/969; pure editor state 424/424 and undo 97/97 (100%). Inherited C++ coverage is not measured here.

TDD first rejected the absent cleanup command. Session regressions then reproduced leftover part/selection after final-node deletion and failure to treat cleanup as part of the original transaction. Nine new tests cover:

- Explicit target validation: missing, duplicate, nonempty, locked, hidden and disabled parts; byte-preserving empty target list.
- Missing node containers and incomplete/unknown component references remain untouched; the new XML cleanup boundary measures 39/41 lines (95.12%).
- Nested/unknown component content and ordering, known linked-profile repair, named presets/non-UUID references, unknown attributes and opaque assets.
- Direct node removal and Cut/session selection deletion, unrelated empty/template preservation, remove-then-add batches, explicit cleanup earlier in a batch, atomic failure, part/node selection pruning, exact one-step Undo/Redo and save/reopen.
- Pinned-core generation of the remaining 16-triangle part after deleting its companion, and default geometry after deleting a linked profile. Low-level document node removal intentionally still preserves an empty part until explicit cleanup; its older compatibility test remains valid.
- Controller clearing of the final part/preview without a false generation failure, with exact Undo and Redo recovery.

Native QA reused the same existing QA bundle/path/identity and a disposable Capsule.ds3 copy. After loading, Command-Shift-A selected three nodes. Delete Selected Nodes removed all nodes/edges and the sole Parts row; the mesh cleared without an error. One Undo restored three nodes, two edges, the part and its 80-triangle preview; Redo repeated cleanup. Undo + Save restored a byte-identical fixture. Rendered empty/restored states were inspected without inventing an unavailable reference-design baseline.

A coordinate click on the overlapping origin/Node 2 now selected Node 2, completing that physical hit-test check from #45. Physical drag still returned the computer-use service error `noWindowsAvailable`; Escape exited the mode unchanged. Actual held-drag cancellation and Front/Side drag routing therefore remain tracked in #45. Full M2 parity, rotated-profile differential checks and VoiceOver certification are not claimed. See [ADR 0024](adr/0024-empty-part-cleanup.md).
