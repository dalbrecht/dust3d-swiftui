# ADR 0142: Explicit component subtree deletion

Status: Proposed

## Context

Qt exposes Delete for selected component rows (`part_manage_widget.cc:426–433`).
`document.cc:988–1023` removes descendants and each linked part through
`removePartDontCareComponent` (`923–959`), regardless of hidden, disabled or locked
flags. Only `partId` links are interpreted (`document_component.cc:8–13`);
unknown link types do not prevent ordinary child recursion. Native hierarchy
likewise retains children independently of link kind.

## Decision

Add a pure, bounded `ComponentDeletionPlan` and one document command for explicit
row targets. Preflight every raw requested identity before deduplication. Match
component IDs, known part references, node owners and edge endpoints with exact
UTF-8 bytes, matching the core's structural string maps. Never reinterpret opaque
links, UUID spellings or canonically equivalent Unicode references.

Remove the selected XML closure. Native supports multiple component instances of
a part, unlike Qt's single-owner assumption: remove a candidate part and graph
only after its last surviving known `partId` reference disappears. Consider only
parts referenced from the deleted closure; do not collect unrelated orphan or
template parts. A dangling known-part row remains deletable as metadata repair;
a missing selected row rejects the whole operation. Remove edges owned by a
removed part or incident to a removed node, including native-importable independent
edge ownership.

Retain all assets, rig/motion metadata and incoming `cutFace` and `wrapBindTo`
references exactly. Mirrors regenerate from source-part settings. Do not reuse
graph normalization or EmptyPartCleanup, whose reference rewriting and splitting
are a different operation. Explicit component management ignores graph edit flags;
ordinary graph editing keeps its existing lock policy.

The target computes outermost-root labels with an indexed, visited descendant
closure, avoiding repeated shared ancestor walks on the main actor. A functional
baseline covers 128 selected leaves below 64 shared parents and selected-ancestor
coalescing; it passed before the complexity correction, not a fabricated timing RED.

Capture document/revision, selection and constraint epochs with explicit contextual
row identities. Stale, unavailable, busy, stopped and cancelled intentions cannot
retarget a later selection. Stage actor publication and support one exact document
Undo. Existing history does not restore transient selection; publication prunes
removed selections. Contextual deletion uses the menu's row set rather than the
previous model selection. The destructive control states that contents are removed;
intentional undoable Delete has no routine confirmation. Keyboard routing belongs
to the component list, not a new global bare shortcut or event monitor.

## Verification

TDD logs preserve missing-API RED, canonical-Set request-collapse RED, raw-selection
projection RED, and subsequent domain/model/Store GREEN. Pure cases cover opaque
subtrees, shared/last references, dangling repairs, independent edge ownership,
soft references/assets, exact Unicode requests, history and ABA rejection. Store
services are fully stubbed, including animation metadata, so hostile pure fixtures
never reach native code. Hosted controls render in both appearances.

The exact focused suite passes 15 tests. A hosted contextual deletion retains the
same native table and first responder. The offscreen NSHostingView is not a key
window and lacks SwiftUI scene command focus; direct NSTableView keyDown, key
interpretation and window key-equivalent probes did not deliver onDeleteCommand.
Those diagnostic failures are preserved outside the test target, rather than
claimed as a product failure or hidden behind direct-action keyboard proof. Apple
documents onDeleteCommand for the focused view; the standard List-only route is
retained. Actual scene/physical List Delete delivery remains unverified while the
desktop is locked. No global key handler or focus-stealing workaround is added. New bounded native inputs require separate source/hash admission
before execution. No production core revision or package dependency changes.

A separately audited ordinary native family uses explicit nonzero origin and two
finite, disjoint, single-node Uncombined sources with no modifiers, rig or imports.
Exact-hash guarded Store delegates accept only source, independently authored
remainder and empty archives. Actual contextual deletion matches both independent
preview triangles and current baked geometry, with successful Undo/reopen/redo and
an empty state containing neither stale preview nor baked geometry nor errors.
The one-method native run passed on unchanged production core48b; linked host,
source digest, fixture and package identities are preserved before/after.

The first native run's sole failure was an independently authored empty oracle
serialized once rather than twice. Foundation adds `standalone="yes"` on the
second header/model parse, accounting for exactly 34 bytes. Preserve that failure
and the original 222-byte oracle as test-construction evidence, not an engine
failure. The corrected independent 256-byte archive passes a Document-only two-
delete byte comparison and the separately reapproved native run; no production
serialization or geometry assertions were weakened.
