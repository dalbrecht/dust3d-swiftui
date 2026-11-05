# ADR 0124: Ordered node reduction

Status: accepted; local native release gates passed on 2026-11-01.

## Context

Qt's node reduction preserves the first incident edge and removes a degree-two node and its second edge. Selected nodes are processed sequentially in UUID order within one history batch. Incident order is initialized by the snapshot edge map on load, but live edge additions and in-place replacements preserve list positions. Reconstructing a sorted adjacency map for every command changes which metadata survives adjacent reductions.

## Decision

Provide an atomic batch document command and a matching read-only availability query. Skip absent or non-degree-two selected nodes as Qt does; reject unsafe editable-degree-two topology atomically. Preserve the retained edge's endpoint orientation, full XML subtree, graph ownership and unrelated assets. Do not create new identities.

Carry process-local incident ordering as a value within immutable document snapshots. Initialize from raw archive edge-ID ordering on load, and preserve ordering through topology edits, midpoint insertion, archive reconstruction, asset merges and paste. Paste follows original source edge ordering before identity remapping. Reduction replaces the second edge's slot in the surviving neighbor's list in place.

Undo and redo restore both archive and incident order. Transaction semantic equality includes that order because it affects future reductions, while persisted dirty state remains based on archive bytes. Order-only changes do not change geometry or justify invalidating mesh inputs.

Expose one model/session/store action for selected nodes. Inspector and Canvas menu share availability and busy-state checks. Existing snapshot publication removes only selections whose nodes were removed. No new shortcut or core dependency upgrade is required.

## Verification

Test reversed XML edge order, both selected UUID orders, adjacent reductions with edge order AB < CD < BC, mixed eligible selections, midpoint/reduce before and after reload, asset/metadata/paste preservation, transactions and undo/redo. Validate pinned-core preview, per-window routing and inspector rendering before the full native gate. Native keyboard and VoiceOver acceptance remain separate evidence requirements.

Local checkpoint tags require clean source, passed native gates and verified package identity. No remote publication follows from this ADR.

Local validation: 257 isolated document tests, 34 combined focused tests, and full native gates passed (60 support, 1,166 XCTest, configured coverage, Qt-free linkage, isolated bundle rebuild/signatures). Four batch inspector states were rendered. Degree-ineligible selections skip; repeated-neighbor/self-loop reduction and unsafe ownership are rejected atomically. These gates do not establish physical keyboard or VoiceOver acceptance.
