# Local selection alignment verification

Full `make ci` passes 207 tests, formatting, both native builds, coverage and Qt-free linkage checks. Document coverage is 1797/1872 (95.99%); model 849/855 (99.30%); pure editor state 391/391 and undo 97/97 (100%). C++ coverage is not measured by this report.

The new cases first failed to compile against the absent feature. Tests now assert expected coordinates for all six local alignments, preserving radii, readonly nodes, opaque assets and exact archive undo/redo. Every transform also runs with all interaction locks enabled. Additional actor tests cover hidden/locked/disabled selections, editable means, individual axis locks and one-step history; no-op empty/single/readonly/already-aligned selections preserve redo. Real pinned-core integration generates a nonempty mesh after each alignment on a diagonal three-node capsule whose untouched axis retains noncoincident geometry.

Native QA used an isolated app and asset-bearing diagonal capsule, leaving the original user apps untouched:

1. Selected all three nodes and inspected the six native inspector menu choices.
2. Applied Front X alignment and saved. All centers visibly aligned in Front view. Independent archive parsing confirmed X=0.5, untouched Y/Z/radii/IDs, unchanged edges/parts/components and exact opaque binary data/non-positional asset metadata.
3. Undo and Save restored the entire original archive byte-for-byte. Redo and Save restored the exact edited archive bytes.
4. Undid, enabled X lock, then applied Front X/Y alignment. Independent parsing confirmed only Y became 0.5 and original X values remained 0.3/0.5/0.7.
5. Switched to Side view and applied Side Z alignment. Parsing confirmed Z=1 with the locked X coordinates unchanged; the native preview settled to an 80-triangle mesh with no stale/error state. The intentionally overlapping Side projection remained inspectable through the sidebar. Saved the disposable file and quit QA normally.

No Qt GUI differential, global-origin alignment, descendant-pivot rotation, VoiceOver or full M2 parity is claimed. See [the decision](adr/0018-local-selection-alignment.md).
