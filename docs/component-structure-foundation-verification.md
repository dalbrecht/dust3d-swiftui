# Component structure foundation verification

Regression-first failures preceded the missing structural commands and actor grouping API. Eight document tests cover root/nested grouping, source-order/nonconsecutive selections, opaque links and child XML, asset/graph/part-state preservation, intentional group-setting removal with exact undo, root/group destinations, same-parent and empty-group no-ops, self/descendant cycles, missing/ambiguous/unsupported targets, fresh-ID bounds, component count/depth limits, and unsupported node geometry retention. A further input-bound regression failed before capping the supplied identity list ahead of Set allocation.

Net-zero group/ungroup and reparent transactions restore exact original bytes and retain an existing redo stack. Nonconsecutive grouping changes adjacency intentionally; Undo is the exact inverse. A session test verifies fresh UUID allocation, independent actors, atomic cyclic-batch rejection and deleted group selection pruning without revival through Undo.

The pinned-engine integration test groups, reparents, nests and ungroups a disjoint two-part union. Every encoded/reopened stage retains two nodes, two parts, 32 triangles, finite positions/normals and matching bounds. Five-step Undo restores the exact initial archive; Redo restores the resulting component order. This is engine integration evidence, not Qt GUI or modifier-combination parity.

Full `make ci` passes 320 XCTest tests, strict native builds, formatting, coverage gates and Qt-free linkage. Measured coverage: structural XML adapter 115/120 lines (95.83%; residual Foundation parent/root and optional-child consistency fallbacks); document overall 2167/2252; editor model overall 1309/1315; pure editor state 495/495 and undo 97/97; mesh 66/67. Inherited C++ and whole-app coverage are not measured by this report.

No new rendered UI is introduced. Native multi-component selection, Group/Ungroup controls, a searchable destination picker, stale-draft rejection and preview orchestration follow in the next stage under #62. Qt differential checks, deep/minimum-size usability and full accessibility acceptance remain pending. See [ADR 0034](adr/0034-component-structure-foundation.md).

An unsupported-parent regression failed for grouping and ungrouping beneath part-linked/opaque components. Those writes now reject before mutation; moving subtrees out still preserves the parent links and remaining children.
