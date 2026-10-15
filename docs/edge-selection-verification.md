# Edge selection verification

Full `make ci` passes 164 tests, formatting, both native builds, coverage and Qt-free checks. Document coverage remains 1596/1670 lines (95.57%); editor model is 805/811 (99.26%), pure editor state 364/364 and undo history 92/92. Inherited C++ coverage is not measured.

Seven edge-selection regression tests cover exclusive transient selection, invalid-ID atomicity, read-only protection, reversal/deletion and exact undo, normalized actor deletion, low-level deletion consistency, front/side segment picking, tolerance boundaries, endpoint clamping, document-order ties, collapsed projections, hidden/missing endpoints and invalid inputs. Tests failed before implementation; the additional low-level deletion test also failed before its consistency fix.

Native verification used an isolated QA bundle, leaving the main running apps and unsaved user work untouched:

- Opened an asset-bearing three-node/two-edge capsule: 80 triangles, no undo history. Clicked between endpoint handles in Front view; the first edge became selected, with directed identity/endpoints and enabled Reverse/Delete controls. Selection alone did not dirty the file.
- Reversed that edge: its identity remained selected and the sidebar/inspector direction changed. Pressed Delete: all three nodes remained, one edge remained, selection was pruned, two normalized parts rendered 176 triangles.
- Saved the deleted-edge result. Independent archive/XML inspection confirmed three original node identities, one edge, two parts, exact embedded binary asset bytes and unknown asset-header metadata.
- Undo restored the edge and 80-triangle model without reviving edge selection. Another Undo restored original direction. Sidebar selection worked; Select Endpoints selected exactly two nodes and cleared edge selection.
- Switched to Side view and picked an edge between node handles. Clicking the shared endpoint selected the node instead. Delete in a focused coordinate field removed draft text without deleting graph objects.
- Restored and saved the disposable source. Byte comparison against the original asset fixture was exact.
- Opened a separate locked-part fixture: edges remained inspectable; Reverse/Delete were disabled with a lock explanation. Delete did not change nodes, edges, dirty state or Undo/Redo availability.
- Quit the QA app normally after verification. Inspected the rendered canvas/sidebar/inspector visually.

This does not certify VoiceOver, all keyboard navigation preferences, oldest-supported-macOS, very large graph performance or Qt GUI differential parity. Marquee remains node selection; simultaneous edge multiselection, subdivision, reference images and later M3–M8 features remain separate work. No core pin, C++ source or archive format changed.
