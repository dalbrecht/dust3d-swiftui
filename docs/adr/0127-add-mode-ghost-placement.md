# ADR 0127: Add-mode ghost placement

Status: accepted; local native release gates passed on 2026-11-01.

## Context

Qt Add mode maintains a ghost cursor, preview edge and radius before committing placements on left press. Native immediate Add Node/New Part commands do not provide this interaction. Preview movement and radius changes must remain outside document history.

## Decision

Use a pure transient placement value, held per window by the editor store, with mode identity, captured document/selection context, frozen projection, anchor, ghost position, scene radius and duplicate-placement bookkeeping. Pointer updates perform projection math without reparsing the document through the actor. Document/session remain authoritative for atomic graph commits.

The ghost defaults to 32 scene points, retains unanchored radius across reentry, and has a one-point preview minimum. Anchored activation inherits the anchor radius. Minus/equal and wheel change a visible ghost by one scene point without editing existing nodes or history. Placement converts by actual canvas height and clamps committed radius to 0.001...1. Render the requested radius through the frozen native projection, using the same visual ring limits as ordinary nodes. For a requested radius outside commit bounds, retain the uncapped request but show the would-be committed minimum/maximum in a nonfatal visible and accessible notice; do not silently replace the requested preview. Initial anchor inheritance uses Qt-effective clamping without changing imported archive values.

A single effective selected endpoint of degree below two becomes the anchor; degree-ineligible selection starts a new part. Read-only anchors cannot be extended. Extensions preserve the hidden coordinate and choose direction from the anchor's first live incident edge. Valid connection targets use existing joining policies and exit mode; invalid targets fall through to placement. Suppress successive duplicate coordinates within 1e-6, advance the chain only from a committed receipt, and give each placement/connection one undo entry. Creation ignores movement/radius interaction locks, while enforcing ownership, identities and quotas.

Native shows one plane at a time rather than Qt's paired profiles. New-part hidden depth therefore uses supported document origin, otherwise 0.5; extension depth follows its anchor. This is an explicit native coordinate policy, not a claim of identical Qt width/4 profile seeding. Existing 3D document/inspector editing remains available.

Keep 2D bounds/projection stable while placing; refit on exit. Geometry, plane, document, undo and window lifecycle changes cancel stale placement context. Preserve existing immediate creation controls separately. A narrow native canvas input boundary owns left-press/hover delivery; SwiftUI owns ghost presentation, and model/session owns graph state. Representable updates must not synchronously mutate SwiftUI state.

Cancellation before commit produces no edit. If a same-document/current-request placement already committed, publish its receipt even if mode cancellation arrives afterward, but do not rebase the cancelled ghost chain. Do not weaken generic stale-request protection. Each in-flight placement has its own identity: cancellation invalidates it, and a late completion may clear only its matching request. A replaced document's completion cannot unmark a newer placement or suppress its cancellation. Selection-only exit refits against the newly published snapshot. Node responder identity includes the tool epoch, so a held press cannot become a new-tool selection on release.

Validate projection inversion using a known bounded document point; a fitted canvas corner may lie beyond the document coordinate limit. Actual pointer updates still reject out-of-bounds positions without changing the accepted ghost.

## Verification

Test transient radius/preview/no history, new parts and group destination, endpoint/degreed fallback, both planes/hidden depth, direction and live ordering, connection/fallback, duplicates/chaining, readonly/locks/quotas, stale contexts and exact undo/redo. Deterministic async barriers cover cancellation on both sides of commit. Hosted input tests cover press timing, event routing, Escape, resize/window/plane/document replacement and accessible mode controls. Validate current pinned-core preview, rendered ghost/edge and full native gates before a checkpoint. Physical input, focus and VoiceOver acceptance remain separate; the Mac is currently locked.

Local verification: all264 isolated model and106 combined focused tests passed. Full native gates passed (60 support,1,245 XCTest, configured coverage including852/852 editor-state lines, Qt-free linkage and isolated bundle rebuild/signatures). Placement-state coverage is145/145lines. Light/dark ghost/control renders were inspected. Native physical pointer/keyboard and VoiceOver acceptance remain open; no product app was launched by these gates.
