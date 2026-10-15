# Native origin controls verification

Full `make ci` passes 221 tests, formatting, both native builds, coverage and Qt-free linkage checks. Document coverage is 1852/1927 (96.11%), model 879/885 (99.32%), pure editor state 415/415 and undo 97/97 (100%). This does not measure inherited C++ coverage.

TDD tests first failed against missing origin snapshot/global-transform/controller APIs. Five new model tests cover every origin axis lock, validation before masking, unavailable-origin initialization, radius independence, readonly selections, all six global alignments, atomic missing-target failure, local alignment independence and actor history. Two controller tests cover input parsing, nonfinite/bounds errors, stopped state, redo preservation, preview regeneration and missing-origin recovery/Undo/Redo. Existing transform cases now exercise all global choices with locks/assets/exact history; the pinned-core integration generates valid meshes after all six local and all six global alignments.

Native QA used isolated bundles and disposable asset-bearing fixtures:

1. Expanded Document Origin, edited X from 0.5 to 0.6 and saved. Independent parsing confirmed only originX changed; nodes/edges/parts/components and opaque asset bytes/unknown asset-header metadata remained intact. The 80-triangle preview regenerated without moving canvas nodes.
2. Entered an invalid draft and used Reset Draft; it returned to the stored value without a history edit. Toggling X lock disabled/re-enabled its field.
3. Selected three nodes and used Front Align X to Document Origin. Saved X values were all 0.6, distinct from their local mean 0.5. Undo/Save restored the exact origin-only edited archive; a second Undo/Save restored the complete original file bytes.
4. Inspected the final labeled X/Y/Z controls and shortened Reset Draft button in the rendered UI.
5. Opened a fixture without origin attributes. Global commands were disabled, local commands remained enabled, fields were empty and explicit initialization guidance appeared. The inherited core reported a missing-origin generation failure (`stod`); the graph and saving remained available. Input validation surfaced an incomplete draft during the automated interaction; after all draft bindings had settled, explicit Apply of (0.5,0.5,1) recovered an 80-triangle preview and cleared the failure. The new controller regression verifies this recovery and history behavior without UI automation timing.
6. Saved the disposable fixtures and quit QA normally; the user's original editor/viewer remained untouched.

No origin marker/dragging, automatic settlement, full Qt zero-origin semantics, VoiceOver certification or full M2 parity is claimed. See [the decision](adr/0020-native-origin-controls.md).
