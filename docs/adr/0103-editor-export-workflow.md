# ADR 0103: Bind accepted editor snapshots to the export service

Status: Local store workflow; native encoder/menu binding pending (#146).

The model and file service do not by themselves capture the active window's
accepted document. Inject an optional DocumentExportFileService into EditorStore;
production defaults to nil, so `canExport` remains false. No preview encoder,
external executable or production core pin change fills the capability gap.

The workflow requires an accepted successful load whose document identity matches
the current snapshot. A failed replacement retains its original cause and cannot
export the old preview as if it were the requested file. Capture snapshot and
EditorExportTarget together, then use both pre-encode admission and the serialized
EditorSession publication coordinator. The caller supplies its original source
URL for alias protection. Encoding uses the captured archive, never rereads that
source, and the result never calls onDocumentChanged or marks history saved.

The existing isWorking barrier blocks overlapping edits, Save, Undo and a second
export while the request runs. Encoding and filesystem work remain off-main.
Reload and stop cancel the owned task; caller cancellation is forwarded using a
cancellation handler. A request UUID prevents an old completion releasing a newer
operation's barrier. Return committed success without checking cancellation after
publication; tag its receipt with the captured document identity/revision, target,
format, byte count and original warning. A receipt from a replaced document must
not be relabeled by a future UI caller. Original native/document/filesystem errors
propagate; active non-cancellation errors retain their message in the store.

Tests use a suspended injected encoder, a no-native preview boundary and small
owned files. They verify current unsaved bytes, exact Undo/source preservation,
no document publication, one in-flight request, independent capability state,
failed-load rejection, reload/stop/caller cancellation and original typed errors.
These are store/service acceptance checks, not native export, AppKit panel/file
permission or real close/quit acceptance. No production Export command or changed
UI is exposed here. The full local `make ci` passes 45 build-support tests and 966 XCTest cases
(120.128 seconds), formatting, coverage gates, Qt-free linkage and isolated bundle
rebuild/signature checks. Five workflow tests use no native export or app control. Native
binding, scene identity/source URL wiring, UI progress/diagnostics and large-file
responsiveness remain required. All quarantines and pin41af7d4c remain unchanged.

Coverage export records 6/6 executable lines for the receipt/error type and
1,033/1,148 (89.98%) for the entire EditorStore file. The latter includes existing
editing/UI routing and is not a scoped export-method or 95% shell-coverage claim.
The configured library/domain coverage gates pass; wider store tests and native
panel/close/permission acceptance remain required before full release acceptance.
