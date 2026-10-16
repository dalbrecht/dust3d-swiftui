# Component hierarchy foundation verification

Regression-first tests failed for the absent hierarchy API and component-name command before implementation. A second regression failed when unknown child tags carrying IDs were omitted; the query now rejects that unsupported generator input explicitly.

The full `make ci` gate passes 298 XCTest tests, strict native builds, formatting, coverage checks and Qt-free linkage. Three document tests exercise XML preorder, ordered direct children, parent IDs, part/opaque link interpretation, empty trees, duplicate/missing identities, duplicate containers, unknown tagged identities, the 10,000-component cap, UTF-8 name limits/control rejection, no-op byte preservation, unknown XML and binary assets, reopening, net-zero transactions and exact undo/redo. A session integration test covers selection/lock retention and failure of a multi-command batch without partial publication or history changes.

Measured coverage: component helper 77/78 lines (98.72%); the remaining region is the optional-root fallback behind the existing validated XML boundary. Document library 1991/2069, mesh 66/67, editor model 1198/1204; pure editor state 461/461 and undo 97/97 remain fully covered. This does not claim the standards' 100% target for every document/helper line or inherited C++ coverage.

The hierarchy format was checked against the inherited `dust3d/base/snapshot_xml.cc`: nested XML defines order; unknown child tags with IDs are treated as components by that parser. We retain unknown link kinds and source bytes, and reject unsupported tagged identities only when explicitly interpreting/editing this hierarchy. Ordinary archive preservation does not require hierarchy interpretation.

No new rendered UI is introduced. Native tree selection/inspection, grouping/reparenting/reordering, modifier editing, ancestor lock semantics and Qt geometry/GUI differential acceptance remain open in #62. See [ADR 0031](adr/0031-component-hierarchy-foundation.md).
