# ADR 0088: Bounded editor preview scheduling

Status: implemented locally for #243; local gate passed; automated review and hosted CI pending.

## Problem

The existing serial Task tail preserves ordering but lets obsolete previews retain
archive data while each queued Task waits for its predecessor. Cancelling a queued
Task does not interrupt that wait. The editor already guards publication with
request IDs and retains its last valid mesh; those policies must remain unchanged.

## Decision

Keep one active backend operation, one latest waiting preview archive, and at most
two metadata-only reset barriers. Distinct PreviewWork and ResetWork values own
typed continuations. A new waiting preview immediately cancels the old waiting
continuation. Cancellation of a waiting request removes it immediately; cancellation
of active generation is relayed cooperatively and its completed output is rejected.
No native algorithm is forcibly interrupted.

A reset invalidates any waiting preview for that scope. A scope with no current or
active context needs no backend reset. Relevant resets serialize behind active work
and before the newest waiting preview; they do not displace the new archive. Reset
callers retain original backend errors. The fixed cleanup backlog reports a typed
scheduling error when full instead of retaining an unbounded chain. Cleanup continues
even if its caller is cancelled. Existing EditorStore logging remains the boundary
for secondary cleanup failures, which do not fail a document write.

Actor-isolated dispatch never overlaps backend generation/reset operations across
suspension points. Existing source-output fallback, native session ownership,
cache diagnostics and per-document scope replacement remain intact. No public
engine API, core revision, document/save format or renderer change is proposed.

## Verification

The existing service failed the regression requiring replaced waiting work to
return CancellationError before controlled active generation completes. The
eleven service contracts pass after implementation, covering latest replacement, queued cancellation, active cancellation, serial
multi-scope behavior, cleanup order/backlog, original reset error propagation and
subsequent successful preview. Use ordinary licensed/procedural documents and
controlled Swift protocol backends, not native fault hooks or crash/signal probes.
The first full gate passed 36 build-support tests and 886 XCTest cases (zero failures; no runtime skips reported), coverage gates and Qt-free checks.
The final bundle-rebuild check initially lacked sandbox process-list access;
its separate authorized rerun passed. The complete authorized `make ci` rerun then passed (exit 0), including
packaging, with 886 XCTest cases, zero failures and no runtime skips reported in 133.86s.
Scoped service coverage measured 190/195 lines (97.44%) and 92/94 regions
(97.87%). These measurements do not establish full editor feature parity.
The unchanged pinned core still emits the known global stitch-debug SVG during
ordinary fixtures; the retained original bytes and modification time were restored after validation.
Filesystem containment is not claimed until the separate core fix is reviewed
and adopted. No quarantined probes were run. Immutable build identity
is generated from materialized source outside File Provider. Operational reboot
backups are locally ignored, preserved unchanged and not compilation inputs.
All builds reuse /private/tmp/dust3d-validator-safe-build and the unchanged reviewed
core pin. The original cloud checkout and its pending regression remain preserved.

## Limits

This bounds the service-owned backlog, not caller-owned data, archive size, native
algorithm workspace, renderer caches or process RSS. It does not introduce process
isolation, deadline/hard cancellation, sandboxing or production worker adoption.
The existing native engine remains cooperative and serialized; hung native work is
still a release blocker. All quarantines and the reviewed production pin remain.
