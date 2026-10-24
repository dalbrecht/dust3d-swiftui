# ADR 0093: Bounded explicit editor recovery copies

Status: Implemented locally; rebased full gate passed on 97afea1b; native command acceptance pending (#248).

The editor needs an app-owned way to retain accepted document state when external
window-control tooling cannot operate its UI. A separate invocation of the same
bundle with `--write-recovery-copies PID` posts a correlation UUID and canonical
positive process identifier to that app identity. The receiver requires its own
PID, so another process sharing the same reusable bundle ID does not capture or
write copies. Untargeted legacy requests are rejected. It does not accept destination paths or document bytes. The receiver
admits one pending task, captures accepted immutable archives on the main actor,
then writes on a filesystem actor. Closed windows unregister weak capture handlers.
Loading, editing and stopped windows report typed failures; one failed window does
not block the other copies. Derived mesh/material failures do not gate capture.

Copies live under the current user's Application Support directory, in
`<bundle-id>/RecoveryCopies/<window-uuid>.ds3`. Stable per-window filenames replace
earlier recovery copies without changing the original, savepoint, selection or
undo history. Production and reusable QA identities have separate directories.
The directory is private (0700), archives and receipts are 0600. Root symlinks and
nonregular inventory entries are rejected. This assumes a trusted user-owned
Application Support hierarchy; it is not containment against a hostile same-user
process modifying paths concurrently.

Pure admission limits a request to 16 windows, retained archives/other regular
files to 4096 and 256 MiB total, and a separate receipt to 64 KiB. Enumeration is
bounded, existing unknown files consume the budget, and nothing is automatically
deleted. Replacement admission subtracts old sizes and writes shrinking replacements
first. Atomic staging may require one additional snapshot's disk space; these are
admission limits, not an OS quota or power-loss durability guarantee.

`latest-recovery.json` version 2 records the exact request UUID and receiving PID, completed/partial/failed/
noDocuments status, copied identities/revisions and bounded failure diagnostics.
Original error objects remain available in the operation report; receipt failures
are secondary and cannot discard successful copies. The command acknowledges only
dispatch, not completion: an old receipt with another UUID is not success. Global
admission/filesystem failures are logged with their original cause and request UUID.
The channel requires a responsive app event loop and cannot recover a deadlocked or
terminated process. It is explicit recovery copying, not automatic crash recovery.

This cannot retrofit an already running older binary. The existing QA process with
a potentially unsaved bone edit remains untouched. Do not execute the new command
against that older executable, rebuild its bundle, or infer native command acceptance
from filesystem/controller tests. Native acceptance on a future safely launched
bundle, broader M1 recovery and full M8 acceptance remain open.

## Verification

Missing-API tests failed before implementation; the retained-file-count regression
also failed before its fix. Seventeen focused cases pass. The full native gate on
73771d7c passed 36 build-support tests and 922 XCTest cases (zero failures or reported
skips), formatting, existing coverage thresholds, Qt-link and isolated bundle checks.
The new pure planner measures 57/57 lines and 36/36 regions; registry/channel
68/68 lines and 30/31 regions; file adapter 133/141 lines and 78/94 regions.
The filesystem adapter's 94.33% line coverage remains below the shared 95% adoption
target; real enumeration failures and native event delivery remain thin boundary
verification gaps. Swift branch coverage was not instrumented. No inherited-engine,
native command, crash recovery or overall feature-parity coverage claim follows.

Supplemental tests verify rejection of an overlapping request before recapture,
retry after an original writer error, cooperative cancellation after one completed
copy with a partial receipt, and rejection of non-file roots/nested directories.
All 20 focused cases pass. Registry/channel regions increase to 31/31; file-adapter
line coverage remains 133/141, so those ordinary tests do not close native enumeration
error-handler coverage. The next full gate covers the supplemental test commit.

## Delivery integration

Replayed the saved recovery stage onto reviewed bone-binding merge d38dbecc.
The integration retains metadata-only rig/bone edits, exact UTF-8 identities and
the tested native text-field boundary. The conflict was limited to the adjacent
recoverySnapshot and rig-setting methods; both remain present. No recovery command
is sent to the older running QA binary. Fresh rebased validation is recorded below; the historical figures above retain
their original implementation scope.

## Rebased delivery gate

Full `make ci` on stable clean 97afea1b passes 36 build-support tests and
930 XCTest cases, zero failures/reported skips (120.893s), formatting, coverage,
Qt-link and isolated bundle/provider checks. The planner measures 57/57 lines
and 36/36 regions; registry/channel 68/68 lines and 31/31 regions. The file
adapter measures 133/141 lines and 79/94 regions (94.33% line coverage), still
below the shared 95% adoption target. Native enumeration error callbacks and
notification delivery remain thin boundary gaps; no artificial failure or
exhaustion probe was used to raise coverage. The protected older QA process
remains untouched and native command acceptance is not claimed. Original SVG
bytes/mtime were restored after the terminal gate. The final follow-up changes
verification prose only.


## Exact process routing follow-up

The untargeted CLI and UUID-only notification each failed a new regression test:
they were accepted without identifying which process sharing the bundle ID should
recover. The command now requires one canonical positive Int32 PID (no zero,
negative, leading zeros, sign, whitespace, overflow or extra arguments). The
receiver validates exactly two bounded metadata fields and matches its actual
process ID before claiming the request gate or capturing windows. The receipt
records the receiving process ID and version 2. PID routing is not authentication
against another process belonging to the same user.

Twenty-two focused cases pass, including same-bundle target/other-process
admission, rejected untargeted messages, malformed metadata, CLI boundaries and
PID-bearing receipts. No distributed notification was posted during these tests.
The receipt remains one bounded latest record per bundle: a later request may
replace it, so collect it and verify BOTH UUID and PID before another request.
Dispatch acknowledgement still does not prove completion. This does not retrofit
the protected older QA process or establish native command acceptance. Full `make ci` at 20fa6861 passes 36 support checks and 932 XCTest cases,
zero failures (118.855 seconds), formatting, coverage, Qt-link and isolated bundle/
provider checks. Registry/channel measures 74/74 lines and 34/34 regions; filesystem
adapter 134/142 lines (94.37%) and 80/95 regions. The native enumeration callback
coverage gap remains below the 95% adoption target; no artificial failure probe
was added. The final documentation follow-up leaves source/tests unchanged.

## Replacement-load provenance regression

Delivery audit found that EditorStore retains its previous accepted snapshot when
loading a replacement fails. Recovery could therefore label that older snapshot
with the replacement FileDocument identity. A test first reproduced a capture
that incorrectly succeeded. Track the latest load's accepted document identity or
original typed failure separately from retained preview state. Capture requires
that accepted identity; a failed replacement surfaces its original error, and a
later successful load re-enables recovery. No snapshot/history bytes are cleared
or changed by this admission fix. Both focused snapshot tests pass; the combined
PID-targeted copy/composition stage still requires its final full gate.

The load admission also records the FileDocument identity supplied by the scene.
A newly registered replacement window cannot capture an older accepted load
before the asynchronous replacement begins. The identity-binding contract first
failed to compile for the missing parameter and now passes alongside failure/
recovery cases. Non-file test/model callers may omit the external file identity;
the application scene always supplies it.

A further ordinary data-boundary test fills a receipt with escaped diagnostic
text. Over-limit JSON preserves the previous receipt and original error objects,
and returns the typed receipt-budget cause. It does not force an OS failure or
change primary copies. All seven filesystem contracts and three snapshot contracts
pass; the final complete gate follows these additional acceptance checks.

## Combined targeted delivery gate

Prepare the final copy/composition protocol together, retaining all PID-targeting,
versioned cancellation and pure sender/receiver fixes instead of publishing the
initial broadcast design. Final make ci passed36 build-support cases and940
XCTest cases (120.717s), formatting, coverage thresholds, Qt-link checks and
isolated signed bundle/provider rebuild. No production core revision or resolved
file changed. No protected QA app was launched, contacted, controlled or rebuilt.

Fresh scoped coverage: plan57/57 lines, registry39/39, request decoder/gate35/35,
and dispatch47/47 (100% lines/regions each). Filesystem adapter134/142 lines
(94.37%) and81/95 regions; native enumeration/error callbacks, defensive invariants
and fallback paths remain unforced. This remains below the95% adoption target;
no OS/fault probe or fake branch is added to fill that gap. Swift branch outcomes
are not instrumented. Actual distributed-notification delivery, entry-point side
effects, callback/log visibility and native recovery acceptance remain manual
boundary gaps. Keep #248/#56 and broader M1/M2/M8 acceptance open. No visual UI
change or full feature parity is claimed.
