# Native component tree verification

Regression-first tests failed for missing tree presentation, component selection and store rename APIs. Four pure-model/session tests and one controller test now cover preorder/depth, display-only fallback names, nested collapse filtering, independent windows, exclusive selection, invalid selection atomicity, unsupported hierarchy diagnostics without destructive repair, exact history, deleted-selection pruning, retained locks, selective document publication and rename validation errors.

Full `make ci` passes 304 XCTest tests, strict builds, formatting, coverage gates and Qt-free linkage. ComponentTree: 51/51 lines and 25/25 regions; pure editor state: 490/490; undo: 97/97. Document: 1993/2071; editor model overall: 1282/1288; mesh: 66/67. This does not claim full-app or inherited C++ coverage.

## Native evidence

Used the existing QA bundle identity and a disposable Capsule-derived archive containing an Assembly group, nested Capsule component and empty root component. Native rendering showed the 80-triangle mesh and source ordering. Group/leaf selection opened the component inspector without adding Undo. Reset discarded a local name draft. Explicit tree menu commands collapsed/expanded Assembly without changing the archive/history; menu selection plus Return exercised the keyboard command path.

Applied Native Assembly, saved through Command-S and independently parsed the archive: group name changed; child name, nested order, all three nodes, both edges and the independent legacy part name remained intact. Undo refreshed the tree and inspector name; settled Save matched the original archive byte for byte. Redo/Save matched the applied archive byte for byte. Inspect Linked Part switched to the existing part inspector and cleared component selection. The fixture was finally restored and saved exactly to baseline.

Rendered inspection found an initially misaligned leaf row. After the final indentation-only adjustment, the rebuilt app displayed aligned disclosure columns and a correctly indented child. No reference design was supplied; no pixel baseline was invented. An explicit native menu supplements the inline disclosure control because the accessibility helper flattens child controls inside list rows.

The native chooser sometimes appeared disabled while inactive. Its advertised Raise accessibility action enabled Open/New controls; this recovered the dialog without another user action or a document discard. The helper also returned noWindowsAvailable for coordinate input and switched to an existing untitled QA window during a focus attempt. Re-querying and selecting the named document recovered observation, but a complete physical-pointer-to-arrow-key navigation check remains unverified. Do not report that attempt as passed. Full VoiceOver, minimum-size/deep-hierarchy usability and Qt GUI differential acceptance remain pending.

Grouping/reparenting/reordering, component modifiers and ancestor lock semantics remain open in #62. See [ADR 0032](adr/0032-native-component-tree-selection.md).
