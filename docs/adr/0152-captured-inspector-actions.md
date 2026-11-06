# ADR 0152: Capture contextual inspector actions

Status: Implemented; full gate and physical acceptance tracked separately

## Decision

Bind single-node Connect to, Delete Node and incident-edge actions, plus selected
edge endpoint selection, midpoint, reverse and disconnect, to their rendered
source context. Prepare metadata availability once per render, then create each
row target with constant-time membership checks. Exact UTF-8 identities reject
unsupported part-reference aliases for mutation while preserving readonly
endpoint inspection.

Reuse CanvasAdjustmentTarget epochs for document identity, source revision,
selection revision and constraint revision. The controller rejects stale dispatch;
the serial session validates again before allocating identities or mutating a
copied state. Initially unavailable actions never acquire later intent. Document
commands retain their original errors and existing deletion normalization; one
mutation publishes one Undo transaction. Endpoint selection publishes no history.
Cooperative cancellation is checked before publication, with existing committed
cancellation delivery after publication.

Generic keyboard and bulk current-selection APIs retain their existing semantics.
No XML parsing, native geometry call or dependency is added to inspector rendering.
The existing bounded Capsule split/rejoin integration covers captured disconnect;
model and controller tests cover mutation, stale context, cancellation and exact
history. Physical pointer, keyboard and VoiceOver acceptance remains outstanding.
No core pin or quarantine change.
