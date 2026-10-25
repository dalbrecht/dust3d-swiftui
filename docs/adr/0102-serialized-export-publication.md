# ADR 0102: Serialize final export publication with accepted editor commands

Status: Local model/service foundation; native encoder/UI binding pending (#146).

ADR0101's asynchronous admission checks leave a gap before the write. An edit can
be accepted in that gap, so they cannot alone guarantee current-revision output.
Keep encoding outside the editor actor. Add `EditorSession.publishExport` to
validate the captured document identity/revision and execute one trusted,
synchronous commit on that same actor without suspension. Accepted edits, Undo,
Open/replacement and other session commands cannot interleave with that commit.
This uses the existing background actor; file writes never move to the UI actor.

The file service accepts a trusted publication coordinator which executes its
supplied commit exactly once or throws. The editor coordinator calls
`session.publishExport(target, publication: commit)`. The commit checks task
cancellation, revalidates source/destination metadata and performs Foundation's
atomic write. The default coordinator retains fixed-snapshot export behavior.
Security-scoped access remains alive through the awaited coordinator. Original
coordinator/write errors propagate. Neither layer checks cancellation after a
committed write, which would incorrectly report an existing output as failed.

The write temporarily serializes accepted editor commands. This is not hard
filesystem cancellation or a responsiveness bound; large-file latency, directory
power-loss durability and concurrent external filesystem mutation remain outside
this stage. Injected coordinators are trusted application code, not untrusted
plugins. Caller-owned snapshot/target pairing remains required. App lifecycle and
native binding must use this coordinator and tag receipts by source revision;
this foundation does not expose an Export command or close M7/M8 acceptance.
The core pin, inherited native paths and all quarantines remain unchanged.

Test-first service contracts initially fail compilation on the missing coordinator.
Owned-file tests cover an edit deliberately accepted after final admission, a
hardlink introduced before commit, current unsaved bytes/diagnostics/Undo state,
and original publication errors. A task-only cancellation flag set after an
actual successful write must still return its committed artifact. This does not
send an OS signal or run a native failure/cancellation probe. Model tests preserve
state/history after a supplied write error. The full local `make ci` passes 45 build-support tests and 961 XCTest cases
(120.075 seconds), formatting, coverage gates, Qt-free linkage and isolated bundle
rebuild/signature checks. All eighteen service contracts pass. This is not native
encoder/UI/lifecycle or large-file responsiveness acceptance. No changed UI requires a screenshot.


## Serialized-publication delivery gate

Prepare corrected `47a2ec12` on the validated export-admission delivery, retaining
source-alias protection. Runtime/test/manifest hashes match the saved tested
stage; only inherited delivery documentation differs. Tests inject ordinary
encoders and publication coordinators against small owned files. They reject an
edit after final admission, retain bytes/warnings/history on success, recheck a
new source alias inside commit, propagate original publication errors, and return
success when cancellation arrives after an already committed write.

Fresh full `make ci` passes 45 support tests and 961 XCTest cases (119.725 seconds),
formatting, coverage, Qt-link and isolated build-only bundle/signature checks.
Service coverage is 71/71 lines and 42/42 regions; Swift supplies no branch
outcomes. No native encoder, Export menu or new app UI is installed. Production
pin, all quarantines and protected QA processes/bundles remain unchanged; known
ordinary pinned fixture SVG writes are not restored. Full M7 acceptance and actual
editor workflow/native binding remain open. Only delivery notes change after this
gate with tested hashes checked unchanged. Require accepted parents, completed
clean exact-head automated review and all CI green before merge.


Apple #262 merged at `78d77eda` after completed clean exact-head automated review and all CI checks green. Full-tree equality across ancestry-only rebase and matching gated source hashes preserve the tested implementation. No native binary executes after rebase; only this delivery note changes afterward.
