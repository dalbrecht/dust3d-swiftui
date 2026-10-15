# Native part controls verification

`make ci` passes 203 tests, formatting, warnings-as-errors builds, coverage and both Qt-free linkage checks. Document coverage is 1797/1872 lines (95.99%), editor model 844/850 (99.29%), pure editor state 391/391 and undo 97/97 (100%). This does not measure inherited C++ coverage.

New tests cover ordered/default metadata, semantic no-ops and boolean aliases, flag/name changes with exact undo/redo, net-zero transactions, escaped Unicode/bounded/invalid names, unchanged component names and opaque extensions/assets, missing-part atomicity, mutually exclusive transient selection, consumed-part pruning, read-only disabled geometry, actor routing and preview state. Integration tests confirm hiding/locking leaves generated geometry intact while disabling one of two parts excludes only its output. A separate default sphere has 16 triangles under the pinned core; the subdivided capsule has 80, and the combined fixture has 96. No generated baseline was automatically blessed.

Native QA used a separately staged application and disposable three-node capsule with an opaque binary asset and unknown asset-header metadata:

1. Selected the part through the native Parts sidebar; selection alone left Undo/Redo disabled. Inspected the rendered layout and accessible state descriptions.
2. Hid/showed the part. Canvas overlays disappeared/reappeared while the 80-triangle mesh remained intact.
3. Locked the part and selected a node; numeric and graph mutation controls were disabled. Returned to the part inspector and unlocked it successfully.
4. Disabled the only part. Overlays and mesh cleared, with an explicit enable-a-part prompt and no failure/stale error. Undo restored the 80-triangle mesh, Redo cleared it, and Undo restored it again.
5. Renamed the part `Body & <head>`, applied and saved. The sidebar updated without changing the mesh. Independent archive parsing verified escaped name semantics, normal restored flags, identical nodes/edges/component names and attributes, exact opaque binary bytes and unchanged non-positional asset metadata. Payload offsets changed to accommodate edited XML.
6. Selected all three part nodes through the inspector; the group inspector reported three editable nodes. Closed/reopened the saved archive; the name, geometry and flags survived, with empty selection and history. Quit the isolated QA app normally; the user's original running apps and unsaved work were untouched.

TDD evidence included missing-API failures, disabled-part creation rejection and Unicode-newline rejection before their fixes. Tests also exercise unassigned-node generation diagnostics. Qt GUI differential validation, VoiceOver/oldest-supported-macOS certification, hierarchy editing, modifier controls and full M3 parity remain pending. See [the decision](adr/0017-native-part-state.md).
