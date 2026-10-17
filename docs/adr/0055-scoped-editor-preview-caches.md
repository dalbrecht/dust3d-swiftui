# ADR 0055: Scoped editor preview caches

Status: accepted for the prototype

## Context

SDK PR #109 provides an actor-owned bounded core session. The editor previously
called stateless loading through a private actor. A document replacement or close
must not retain another document's cache, and asynchronous cleanup must not clear
a newer owner. Derived cache failures cannot block primary editing or saving.

## Decision

Extract an internal Sendable EditorPreviewServing interface and a background
EditorPreviewService actor. Each active scope owns a lazily created SDK session.
A new scope creates a distinct owner. A serial operation tail preserves the old
service's single-job behavior across SDK actor suspension points, including rapid
replacement. Cancelled queued work is checked before creating another owner;
reset remains best-effort and scope-checked. Keep the SDK's 64 MiB default budget.
No C pointers or native ownership move into the observable store.

The store rotates its scope and cancels the current request when replacing,
clearing or stopping a document. Cleanup identifies the previous scope. The
service ignores obsolete cleanup, detaches a matching context before awaiting
its captured owner's reset, and never modifies the current context afterward.
Later operations wait for either completion outcome, so one editor cannot queue
parallel backend jobs merely because an SDK await releases actor isolation.
Unexpected cleanup failures preserve their cause
in privacy-protected logging with the operation scope; they do not mutate a
stopped document's UI or turn a successful write into a failure.

Preserve the existing 150 ms debounce, request identity, cancellation checks,
stale-last-valid mesh, successful empty completion and retry behavior. Accept
cache statistics only for an uncancelled current scope. Clear derived statistics
when starting another request or clearing the preview. Lifecycle callers may
await a captured generation task's cooperative completion without exposing
mutable scheduling state.

Display cache-only diagnostics below the preview as a selectable, accessible
notice, separate from generation/render errors. Valid mesh output, undo/history
and lossless save remain available. No cache status is persisted in the archive.
The viewer continues using stateless loading.

Dust3DDocument.encoded() returns immutable stored Data. Passing it to the actor
is a COW value handoff; this change does not claim to move expensive encoding off
the UI thread or interrupt C++ generation.

## Consequences

Real core tests prove scope reuse and reset, while a suspended service controls
out-of-order completions without native failure hooks or timing-based assertions.
Offscreen light/dark rendering validates the new notice without activating an app.
Retained payload budgets exclude temporary work, allocator overhead and RSS;
an older in-flight job must complete cooperatively before later queued work. Controlled resource
benchmarks, source provenance and Qt differential acceptance remain pending.
This does not complete M3 or editor parity.

See [verification and remaining limits](../editor-preview-session-verification.md).
