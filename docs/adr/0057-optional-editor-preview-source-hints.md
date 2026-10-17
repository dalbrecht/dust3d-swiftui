# ADR 0057: Optional editor preview source hints

Status: Accepted for implementation. Apple issue #114.

## Context

The reviewed SDK can return indexed geometry and source identities/weights from
one cached generation. Future material and rig workflows need source data tied to
the same mesh revision. Source payload limits must not prevent ordinary previews,
editing, or lossless saves.

## Decision

Store mesh and optional hints as one immutable preview output, accepted by the
existing request/scope checks. Expose hints only for a current, nonworking preview;
stale meshes remain visible after failures, with their metadata unavailable.
Source/cache diagnostics remain transient and separate from document history.

Try sourced generation first. Retry once through the existing ordinary API for
native generation/resource failures (statuses 3/4), retaining the original cause.
Those statuses cover both primary and optional source failures, so successful
fallback is required before reporting the issue as nonblocking. Invalid document
and unsupported input failures are not retried. A failed fallback reports both
causes without duplicate text; cancellation does not trigger fallback and is
checked after each successful backend result. Jobs remain serial across awaits.

## Consequences

Optional details can degrade without suppressing valid geometry. Worst-case
fallback performs a second generation attempt; cooperative cancellation cannot
interrupt C++ already running. Both attempts share one document-scoped session.
This introduces no new dependency, archive field, picker, material renderer, or
rig behavior. Source identity presence is a foundation, not parity acceptance.
