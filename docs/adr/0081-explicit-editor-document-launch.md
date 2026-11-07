# ADR 0081: Explicit editor document launch

Status: Accepted

## Context

Unattended native QA cannot depend on a human operating a file picker. On this
machine an initial editor picker exposed disabled New/Open buttons, while Open
from an existing document worked. Later native checks recovered ordinary New/Open
and observed selection controls becoming enabled after object-preview completion.
The underlying role of retained state/registration and latency is unconfirmed
(#170); renderer changes have not been established as its cause.

## Decision

Accept up to 64 distinct local `.ds3` paths in argument order. Each
`--open-document` operand must be absolute. Positional paths can be relative
to the process working directory. Standardize file URLs and reject duplicate
paths, NUL, missing explicit operands, wrong explicit extensions and paths
over 4096 UTF-8 bytes before opening any document.

Skip known platform and legacy option operands. After an unknown option, use
`--open-document` or the `--` delimiter to identify paths unambiguously.
Report the unsupported Qt export-at-launch flags `-o` and `-output`.
Claim the batch before awaiting the first open so lifecycle callbacks cannot
replay it. Report each original document-open error and continue opening
later documents.

Use a narrow AppKit delegate hook to suppress untitled startup for explicit
requests and call `NSDocumentController.openDocument`. SwiftUI `DocumentGroup`
retains file state, coordination, save/autosave and close handling. No second
state container, network control channel or forced process termination is added.
Ordinary startup behavior remains unchanged while #170 is investigated.

## Verification and limits

Pure launch contracts cover batch validation, ordered single dispatch and continuation after an open error. Multi-window launch remains to be verified in the running App.
Native QA opened ImportedSurface directly, then Capsule through standard Open.
Fresh-start New and Open also succeeded in the regular bundle after controlled
same-identity packaging checks. A comparison bundle worked with and without
preview extensions; extension presence alone did not reproduce the failure.
A radius edit to a disposable Capsule copy persisted through normal native quit;
the original fixture stayed unchanged. The scene autosaved, so that run does not
prove presentation of an unsaved-close prompt. The launch flag applies only to
a new process, not an already-running instance. The existing app identity is
reused. A screenshot is an external diagnostic artifact, not a pixel baseline.
