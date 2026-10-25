# ADR 0101: Admit captured exports by document identity and revision

Status: Local model/service foundation; native binding and app coordination pending (#146).

A byte-equal document can be a different open operation or a newer revision after
Edit and Undo. Capture `EditorExportTarget` from the accepted snapshot's document
UUID and monotonic semantic revision. `EditorSession.validateExport` rejects an
unloaded session or mismatched target without changing its document/history.
Interaction locks and selection do not change semantic identity. This target
contains no renderer result and makes no native capability claim.

`DocumentExportFileService.export` accepts a Sendable asynchronous admission
closure. It runs before encoding and again before filesystem publication, checks
cancellation after each await, and propagates the original admission error. No
post-commit admission/cancellation check can misreport a committed write as a
failed export. Callers intentionally exporting a fixed snapshot may omit the
closure; editor integration must capture its document and target together.

This check is not a lease across actors. A document can change after validation
returns. The future app workflow must coordinate its final publication phase with
editing/replacement/close operations and label the resulting receipt by source
revision. This stage does not claim atomic current-revision publication, enable
an Export command, change the core pin, invoke a helper, or lift any quarantine.
The existing save-snapshot guard remains independent and unchanged.

Test-first service contracts initially fail compilation on the missing boundary.
Owned-file tests suspend an injected encoder, perform an edit and exact Undo,
then verify stale rejection preserves previous output. Reopening the same archive
rejects before encoding; current exports with transient locks still publish owned
bytes and original warnings. Separate-window/unloaded checks preserve current
state and history. The full local `make ci` passes 45 build-support tests and 955 XCTest cases
(119.917 seconds), formatting, coverage gates, Qt-free checks and isolated bundle
rebuild/signature checks. These are model/service checks, not native export or
atomic app-publication acceptance. No production dependency or quarantine changes
are included; there is no changed UI requiring a screenshot.


## Export-admission delivery gate

Prepare this stage on source-alias PR #261 at `5d0190b7`. Runtime, tests and
manifest hashes match corrected saved `98b79773`; only inherited delivery notes
differ. Preserve the existing source-alias regression and all earlier contracts.
Fresh full `make ci` passes 45 support tests and 955 XCTest cases (121.175 seconds),
formatting, coverage, Qt-link and isolated build-only bundle/signature checks.
Tests use ordinary snapshots, small owned files and deterministic injected
encoders. The production core pin and all quarantines remain unchanged.

No native encoder, Export menu, protected QA control or new app UI is added.
Admission remains distinct from serialized final publication; the next stage
must bind that write to the owning editor actor. This result does not establish
full M7 acceptance. Only delivery documentation changes after this gate, with
runtime/test/manifest hashes checked unchanged. Require an accepted parent,
completed clean exact-head automated review and every CI check green before merge.
