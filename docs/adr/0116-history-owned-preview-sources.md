# ADR 0116: History-owned preview source identities

Issue: #275. Status: full local gate passed; public review pending.

## Decision

DocumentHistory owns separate process-local geometry and material UUIDs. Each undo
entry captures both with the exact document; Undo/Redo restores all three. Fresh
histories have independent identities even for identical bytes. Rejected commands
and semantic no-ops keep identities. Cancelled or net-zero transactions restore
their starting identities, without altering archive serialization or save state.

Classify only accepted commands, after validating and detecting actual changes.
Stored animation/rig/bone intent, names, reference images and editing visibility
or locks retain preview identities. Part material values and color-image assignments
advance materials alone. Disabled state, component color (copied vertex colors),
geometry and all other commands conservatively advance both. New command kinds
therefore invalidate by default until their input contract is established.

The editor snapshot carries these trusted values. Rendering invalidation now comes
from comparing accepted snapshot identities rather than caller-supplied booleans.
Animation metadata Undo/Redo preserves valid geometry; topology history still
regenerates. Material-only history refreshes materials independently. Successful
and failed generation must pass scope, geometry identity and active-request checks
before publishing mesh, source diagnostics or statistics on the main actor.

This is command/history equivalence within one open document, not arbitrary archive
geometry hashing. Imported replacement documents receive fresh scope and history.
Worker request-byte identity, helper packaging and real containment remain separate
integration work. No opaque owner crosses a concurrency boundary. No quarantined
evaluation or new native failure/cancellation/malformed/pressure probe is added.

## Evidence

Initial pure tests failed for missing previewIdentity. After the history changes,
the store regression failed with three preview calls instead of one across an
animation edit/Undo/Redo. It now passes, and geometry edit/history causes the
expected new calls. Delayed fake tests preserve an in-flight result through
animation history and reject old diagnostics after an identical-byte reopen.

Twenty-six focused tests pass, including existing animation, rig and bone metadata
regressions. The first store test setup omitted animation-list loading and was a
no-op; it was corrected to assert actual document changes before recording the red
three-versus-one result.

Full `make ci` passes: 45 build-support tests and 1,025 XCTest cases with zero
failures, coverage thresholds, Qt-free linkage and viewer/editor bundle rebuilds.
Measured Swift lines: document 3862/3958; editor model 1839/1845; pure editor state
536/536; pure undo/history 121/121. These are scoped metrics, not whole-engine
coverage or complete native acceptance. Existing ordinary boundary tests were
included; no new native probes were added. Completed exact-head automated review
and every public CI check remain required before merge.
