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

Accept `--open-document` followed by one absolute local `.ds3` path at editor
process startup. Bound it to 4096 UTF-8 bytes and reject NUL, relative paths,
wrong extensions, missing operands and duplicate flags. Ignore unrelated system
launch arguments. Claim each request before awaiting so lifecycle callbacks
cannot replay it. Present invalid arguments and original document-open errors
through native error presentation.

Use a narrow AppKit delegate hook to suppress untitled startup for explicit
requests and call `NSDocumentController.openDocument`. SwiftUI `DocumentGroup`
retains file state, coordination, save/autosave and close handling. No second
state container, network control channel or forced process termination is added.
Ordinary startup behavior remains unchanged while #170 is investigated.

## Verification and limits

Pure launch contracts cover validation, single execution and original errors.
Native QA opened ImportedSurface directly, then Capsule through standard Open.
Fresh-start New and Open also succeeded in the regular bundle after controlled
same-identity packaging checks. A comparison bundle worked with and without
preview extensions; extension presence alone did not reproduce the failure.
A radius edit to a disposable Capsule copy persisted through normal native quit;
the original fixture stayed unchanged. The scene autosaved, so that run does not
prove presentation of an unsaved-close prompt. The launch flag applies only to
a new process, not an already-running instance. The existing app identity is
reused. A screenshot is an external diagnostic artifact, not a pixel baseline.
