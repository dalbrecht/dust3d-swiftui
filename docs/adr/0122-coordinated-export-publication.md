# ADR 0122: Coordinated export publication

Status: local implementation for #185; signed sandbox and cloud-provider validation remain open.

## Decision

Keep `DocumentExportFileService` as the shared OBJ/FBX export boundary. After
encoding the captured archive and validating the requested destination, request
per-export `NSFileCoordinator` writing access with `.forReplacing`. The
coordinator's admitted URL is independently checked, security scope is entered
when available, and the output is staged in an item-replacement directory on
that destination's volume. Preserve the existing artifact-returning `export`
API; `exportReceipt` also returns the admitted URL, which the editor displays.

The coordinator callback hands an owned lease to the original caller task and
waits on its private operation queue until publication finishes. Presenter waits
do not occupy the editor session actor or the main thread. The caller retains
its cancellation and task-local context while the session checks its captured
revision and executes the synchronous final alias checks and rename. No
unrelated edit can interleave between the final revision check and rename.
Each request owns its coordinator and cancellation state. The only cross-thread
coordinator call is Apple's documented `cancel()`, protected by a private lock.

Check cancellation after admission, before staging and immediately before
rename. Cancellation before commit preserves an existing destination; a
successful rename remains success if cancellation arrives afterward. Preserve
coordinator and filesystem errors, translating Cocoa user cancellation only when
this request was cancelled. Staging cleanup is best effort and logs its cause.
The source URL and inode protections are checked again for redirected paths and
inside the session-serialized commit. As before, concurrent uncoordinated
filesystem changes and power-loss directory durability are outside this contract.

## Validation and limits

Injected tests cover redirect and source alias, cancellation before publication,
and original coordinator causes. The real temporary-file test holds a coordinated
reader, checks cancellation and verifies an independent destination can proceed;
no application or imported model is launched. A task-local test confirms native
coordination retains caller context. Existing tests cover stale revision, late
cancellation after commit, source paths and hard links, and unchanged diagnostics.
Native generation cannot be preempted by this file coordinator. Sandbox signing,
iCloud and provider-specific redirect behavior need separate release validation.
No core pin, feature quarantine, engine or export geometry behavior changes.
