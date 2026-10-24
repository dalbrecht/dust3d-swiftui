# ADR 0100: Publish captured document exports through an injected encoder

Status: Delivery validated locally; automated review and native binding/UI adoption pending (#146).

The editor has no export service and its production core pin does not yet expose
the new original-geometry APIs. Introduce DocumentExportEncoding as an off-main,
Sendable owned-byte boundary, and DocumentExportFileService as an actor handling
publication. No fallback preview encoder, executable invocation or production pin
change is installed. The next reviewed dependency stage supplies the native
encoder and app commands. This stage does not enable an Export menu item.

Capture a Dust3DDocument value, encode its current archive (including unsaved
edits), and never reread its source path for export generation. The service never
marks document history saved or changes its undo stack. Native adapters must copy
bytes and diagnostics before destroying C handles and serialize inherited engine
calls. Output includes the original diagnostic instead of discarding warnings.

Validate local destination/format and regular-file/directory metadata, reject
source path/inode aliases and destination symlinks, retain security-scoped access
through the asynchronous operation, then revalidate after encoding. Require
nonempty output at most256MiB and atomically publish using Foundation. Cancellation
checks precede work and publication; a committed write returns success without a
post-write cancellation error. Original encoder/filesystem errors propagate.
Concurrent external filesystem mutation, directory power-loss durability and
hard encoder cancellation/resource containment are not guaranteed. The bound
checks returned data, not an arbitrary injected encoder's temporary allocations.

Initial local validation used five real owned-filesystem tests for first-time publication, replacement,
exact captured archive bytes, diagnostics, hardlink/direct source protection,
symlink/wrong-extension/directory rejection, nondirectory parent and empty-output
preservation. TDD began with missing-boundary compiler failures. Initial sandboxed
gates exposed compiler-cache access and existing clipboard-test restrictions;
explicit shared caches and authorized desktop test access resolved them without
source changes or QA-app control. Final make ci passed45 build-support tests and
942 XCTest tests (118.469s), formatting, coverage, Qt-free checks and isolated
bundle rebuild. The service measured57/57 executable lines and32/32 regions
(100% each); Swift coverage reports no branch outcomes. This is not native or
whole-app coverage. No protected QA app was launched or controlled.

Native encoder binding, actual editor export commands, end-to-end unsaved/history
acceptance and full M7 parity remain unverified. Quarantines and pin41af7d4c are
unchanged. This service stage has no changed UI requiring a screenshot.

## Delivery revalidation

On reviewed Apple master after #259, nine service tests passed. In addition to
ordinary publication, unsaved captured archive bytes, source preservation and
exact undo/redo/savepoint assertions, they cover cancellation before admission and
during a suspended encoder, preservation of the original typed encoder error,
and fresh inode-alias admission after encoding. The tests use caller-owned small
files and deterministic injected encoders; no native engine failure, crash or
resource-exhaustion probe is involved.

The final full `make ci` passed 45 build-support tests and 950 XCTest cases
(120.119 seconds), formatting, coverage gates, Qt-free checks and isolated bundle
rebuild. Fresh scoped service coverage is 57/57 executable lines and 32/32 regions;
Swift supplies no branch outcomes. The earlier 942-case result above is historical.
No native export command was exposed or exercised; UI acceptance remains pending.
Protected QA processes/bundles, all quarantines and the core dependency pin are
unchanged. No new screenshot applies to this service-only stage.
