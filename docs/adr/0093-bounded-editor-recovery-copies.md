# ADR 0093: Bounded explicit editor recovery copies

Status: Implemented locally; full gate passed on 73771d7c; native command acceptance pending (#248).

The editor needs an app-owned way to retain accepted document state when external
window-control tooling cannot operate its UI. A separate invocation of the same
bundle with `--write-recovery-copies` posts only a correlation UUID to that app
identity. It does not accept destination paths or document bytes. The receiver
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

`latest-recovery.json` records the exact request UUID, completed/partial/failed/
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
is sent to the older running QA binary. Fresh rebased validation remains pending;
the historical figures above do not retag this delivery.
