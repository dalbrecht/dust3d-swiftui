# Component combination verification

Tracks #62. Decision: [ADR 0038](adr/0038-component-combine-modes.md).

## Automated evidence

New document tests first failed to compile because the typed combination API was
absent. New controller tests first failed for the absent action. After implementation,
all seven new document/session/controller tests pass. They cover inherited enum
spellings, missing/empty and unknown modes, exact legacy true spellings, clearing
legacy component inversion, semantic no-op byte preservation and redo retention,
opaque XML/comments/attributes/assets, hierarchy order, reopen, missing/ambiguous
identities, atomic failed batches, selection/axis locks and exact history.

The controller test uses the actual pinned core and two disjoint single-node
parts. Normal generates 32 triangles. Inversion of the second part leaves 16
triangles with all vertices confined to the first part; undo restores 32 and
redo restores 16. Uncombined regenerates both parts (32). Each actual edit
publishes once, retains camera and selection, and a repeated mode publishes no edit.
This is a pinned-core contract fixture, not a Qt GUI differential corpus.

Full `make ci` passed on 2026-10-16: 346 tests, zero failures; formatting, native
builds, Qt-free linkage and isolated signed bundle rebuild regressions passed.
Measured lines: mesh 66/67, document 2267/2351, editor model 1394/1400,
pure editor state 523/523, undo domain 97/97, orbit camera 33/33.
No inherited C++ or Metal/native UI coverage threshold is claimed.

## Native acceptance

Built and strictly signature-verified the reviewed app, then used the reusable QA
bundle identity `org.dust3d.editor.combine-qa`. The original QA window with
unsaved edits was left intact; native checks used separate copies of synthetic
fixtures. Reuse this identity for later stages rather than creating a new app ID.

Selected the second component in a two-part nested group. Its native Combine mode
picker exposes Normal/Inversion/Uncombined with the expected accessibility label,
identifier and help. Inversion changes the preview from 32 to 16 triangles;
rendered inspection shows the remaining lit part and a readable inspector.
Save writes the chosen component attribute. Native Undo restores Normal and 32
triangles; Undo then Save is byte-identical to the original archive. Redo restores
Inversion and 16 triangles; Redo then Save is byte-identical to the saved edited
archive. Uncombined restores both rendered parts and 32 triangles, and saves.

An independently serialized fixture contains `combineMode="Future"`, legacy
`inverse="true"`, a future attribute and a four-byte opaque asset. Its picker
shows “Unsupported source mode”. Explicit Normal clears legacy component inversion,
regenerates 32 triangles and preserves the future attribute and asset on Save.
Native Undo restores the unsupported display and 16 triangles; Undo then Save is
byte-identical to the original unknown-mode fixture. All QA documents were saved
before normal Quit, leaving the QA bundle available for reuse.

Qt GUI boolean comparisons, overlapping/interacting modifier fixtures and broader
VoiceOver checks remain M3 acceptance work. These native checks do not prove full
modifier parity or Metal coverage.
