# ADR 0121: Original procedural FBX export

Status: Proposed for #286, following #146 and ADR 0118.

## Decision

Use the canonical static FBX C ABI already present in production core revision
48b0ce2d. Configure GEOMETRY mode explicitly, with independent 64 MiB geometry
and output logical payload profiles (configurable positive limits up to 256 MiB).
There is no dependency upgrade, copied C++ adapter or new package dependency.
The geometry path does not request atlas baking, imported geometry, rig or
animation evaluation. DocumentReader rejects model assets before GLB decoding
when this operation supplies no import owner. All quarantines remain.

The Swift actor confines synchronous foreign ownership to one call stack. Sized
options are zero initialized; native cancellation remains nil. Bytes and strict
UTF-8 warning text are copied before deferred destruction. Native retained payload
and byte counts must be ordered and within the configured output quota. Copied
bytes plus warning UTF-8 bytes also share that output quota, with checked
subtraction and a 4096-byte warning cap before copying. These logical limits do
not bound generator workspace, allocator overhead, peak RSS or operation time.
Original MeshLoadingError causes propagate; Swift cancellation is checked before
and after work, without claiming native interruption.

NativeGeometryExportEncoder routes exact captured archives to the existing OBJ
or new FBX encoder, preserving selected errors without cross-format fallback.
One scene-owned EditorGeometryExportWorkflow handles both formats. The former
OBJ-only internal workflow/panel/status/command types are renamed together;
there is no second export task or competing destination sheet per window.

The toolbar Export menu offers OBJ Geometry and FBX Geometry; File exposes both
and retains Command-Shift-E for OBJ. The selected format is captured before the
chooser, determines the extension/content type, and remains attached to the
receipt. Existing source/revision admission, alias rejection, atomic publication,
post-commit success semantics, cancellation/drain and original warnings remain.
Savepoints and Undo/Redo are unaffected. Native panels still require the owning
window and reject unrelated active sheets; no global-window fallback is added.

## Verification and limits

Failing-first injected tests cover budgets, unsupported formats, copied-output
limits, original failures, Swift-only cancellation, exact routing, selected
extensions, stale replacement and destination/source preservation. A regression
initially accepted bytes whose retained warning exceeded the copy quota; the
combined count guard fixes it without foreign rejection probes.

The only added native contract is fresh GEOMETRY-mode export of the ordinary
licensed Capsule, with independent byte ownership across subsequent exports and
source preservation. The broad inherited FBX API test contains malformed-input
and native-cancellation cases, and its Swift smoke uses BAKED mode; neither is
run unchanged as validation for this stage.

Assimp 6.0 independently imported the fresh 9706-byte binary FBX, then exported
an XML inspection dump. Its geometry matches independently imported OBJ source
polygons: 16 triangles and 32 planar quads become 80 oriented triangles, retaining
42 referenced positions, finite unit corner normals and fixture bounds. Assimp
uses different quad diagonals, so validation checks either oriented triangulation
only after proving planarity; it does not weaken a triangle mismatch to a count
comparison. See fbx-export-verification.md for exact scope and reproduction.

Offscreen real SwiftUI menu/status views use sample state and an owned hidden
window, never a protected QA app. Live save-panel, menu/shortcut/focus/VoiceOver,
oldest-supported-macOS and full export acceptance remain unverified. This is
in-process geometry export, not worker isolation or full M7. Baked/textured,
imported, rigged/animated, WAV and batch export remain separate work.
