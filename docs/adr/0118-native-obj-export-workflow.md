# ADR 0118: Native original-geometry OBJ export workflow

Status: Proposed for #281.

## Decision

Bind `NativeOBJExportEncoder` to the existing reviewed core revision `48b0ce2d`.
Keep the canonical C ABI in dust3d-core; do not duplicate native adapters here.
A background Swift actor calls the serialized original-geometry bridge and copies
immutable bytes/warning before destroying the foreign handle. It rejects unsupported
formats and input/output policy violations before publication. The default output
payload quota is 64 MiB (explicit custom limit up to 256 MiB), not a workspace/RSS
bound. Imported model assets are rejected by this pinned original-export reader
before GLB decoding; no preview reconstruction or quarantined GLB path is used.

Each document scene owns one observable workflow and narrow injectable destination
chooser. The workflow captures an `EditorExportTarget` before presenting a sheet;
`EditorStore` validates that same target through existing actor-serialized admission
and atomic publication. A changed revision cannot silently export a newer state.
Existing source path/inode checks, savepoint and history invariants remain intact.
The scene passes its actual source URL, including subsequent Save As changes.

A tiny `NSViewRepresentable` binds a weak document window to `NSSavePanel`.
SwiftUI owns commands, progress and state. SwiftUI `fileExporter` was considered,
but owns the final write and would bypass the existing serialized publication
transaction. No global key-window lookup or process-wide panel owner is added.
Admission rejects an unrelated active sheet. Programmatic cancellation is idempotent;
root teardown cancels the owned workflow without asking a human to dismiss it.

Cancellation checks precede/follow native generation and precede publication. No
native cancellation token is passed. A cancelling task retains ownership until
actual drain; the UI says “Finishing current export…” and disables duplicate work.
An already committed receipt remains success after late cancellation. Original
errors remain typed and shown through the existing banner; native warnings remain
beside the successful receipt. Export never marks the source saved.

## Verification and limits

Focused fake tests cover chooser cancellation/failure, duplicate admission, source
replacement, stale captured revisions, hard-link source protection, retained error
causes, owned lifecycle stop and pending encoder cancellation without publishing.
Only the existing licensed healthy Capsule exercises native output, twice to verify
copied owner lifetime. Policy/negative/cancellation tests never dispatch native work.
The native reader/source audit excludes GLB decoding and the inherited Snapshot
writer from this export call chain. All existing quarantines remain in force.

Offscreen rendering inspects the canonical feedback view in light/dark appearance;
no application window or native sheet is shown. See `obj-export-ui-verification.md`.
Live panel interaction, window focus, keyboard/VoiceOver and GPU behavior are not
verified by these captures. Original OBJ positions/faces are the supported scope;
UVs/materials/imported geometry/rigs/animation and independent consumer re-import
remain open. This does not complete M7 or full editor parity.
