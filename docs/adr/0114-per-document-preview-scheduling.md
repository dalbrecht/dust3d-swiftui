# ADR 0114: Bounded per-document preview scheduling

Issue: #271. Status: local implementation; full delivery gates pending.

## Decision

Keep native entry globally serial, but retain one latest waiting request for each
document scope instead of one global waiting request. A pure value queue preserves
FIFO scope order when replacing that scope's value. After its turn starts, a new
request for that scope joins the tail, behind other waiting documents. Eight
waiting scopes bound archive retention; the active job is separate. A ninth new
scope receives `EditorPreviewSchedulingError.previewBacklog`, while replacement
within an existing scope remains possible. No automatic retry is implied.

Replacement resumes only the old same-scope continuation with cancellation.
Explicit cancellation and reset remove matching work without displacing another
scope. Existing two-barrier cleanup priority and serial backend entry remain.
The actor exposes bounded pending preview/reset counts for scheduling diagnostics.
Document writes, undo and core dependency identity are unaffected.

## Evidence and limits

The initial four pure queue tests failed to compile for the missing type, then
passed. Five pure tests now cover FIFO, cross-scope retention, replacement at
capacity, removal/reuse and zero capacity. Three actor tests use a gated recording
backend that never parses a document or calls the engine. They verify execution
order `[0, 3, 2, 4]`, one active job, capacity rejection and same-scope replacement,
waiting cancellation/reuse and scope-specific reset with cleanup before surviving
work. Queue/cleanup counts establish submission barriers before releasing work.
Original fake backend errors reach callers unchanged.

All eight focused tests pass with coverage. `ScopedPreviewQueue.swift` measures
28/28 lines, 20/20 regions and 10/10 functions. The fake-only service profile is
149/198 lines (75.25%), not complete service or application coverage. Swift reports
no branch-outcome metrics. Compilation uses strict Swift 6 and the existing shared
scratch/caches. No native generation, fault, cancellation, pressure or UI probe ran.

Repository formatting/shell lint passes. All 45 build-support tests pass with
explicit shared compiler-cache paths. An initial support run failed while compiling
its ordinary identity helper before launch; rerunning with those cache paths passes.
These support checks do not replace the pending full application gate.

The full local `make ci` gate has not run: source audit confirms the pinned core's
ordinary stitching path still writes `/tmp/stitch_loop_debug.svg`. The current
restriction forbids modifying that global artifact. This is a pending gate, not a
pass or a reason to execute the path and restore the file afterward. No production
pin change, quarantine removal or test exclusion is claimed as full verification.
Full service regression, coverage gate, CI/review and native app acceptance remain
pending. This stage alone does not complete XPC editor adoption or full parity.
