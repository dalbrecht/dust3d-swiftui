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

## Pending native acceptance

The inspector picker is implemented and compiles, with an accessibility identifier,
keyboard-native Picker semantics and explicit unsupported-source text. Its final
rendered/menu/open-save-Undo/Redo acceptance remains pending. The existing QA
editor has unsaved interactive edits, so its process/document/bundle were preserved.
Do not treat controller tests as evidence that the native picker was exercised.
Qt GUI boolean comparisons, overlapping/interacting modifier fixtures and broader
VoiceOver checks remain M3 acceptance work.
