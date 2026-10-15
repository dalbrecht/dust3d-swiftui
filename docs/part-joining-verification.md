# Cross-part endpoint joining verification

`make ci` passes 117 tests, formatting, both native app builds, coverage gates and Qt-free checks. Line coverage is 1122/1162 (96.56%) for the document library, 576/582 (98.97%) for the editor model, 325/325 (100%) for pure editor state and 92/92 (100%) for undo history. This does not measure inherited C++ or native UI/GPU coverage. The core revision and C++ standards are unchanged.

Document tests exercise all four endpoint orientation combinations, target chain reorientation, same-part loop closure, outward extension, source-settings replacement, retained node/edge IDs and unknown fields, opaque assets, namespace handling, repeated/nested component references and unrelated component-like extension tags. Consuming a target part removes its leaf component settings; references with actual child components become groups so descendant geometry survives. Snapshot undo restores all consumed settings and original bytes, and redo restores the exact joined bytes.

Known part/node `cutFace` references are redirected from the consumed target ID to the source. Direct and indirect resulting cycles throw the typed `cyclicProfile` error before publication. Arbitrary unknown fields are not rewritten. Missing/unassigned/read-only/interior endpoints, duplicate/self edges, branching members and partially disconnected target chains reject atomically. Existing low-level `addEdge` remains a same-part primitive; product actions use the validated `joinNodes` command.

Pure state tests cover endpoint target availability across parts, read-only and multiple-selection restrictions, locked-axis topology behavior, and extension away from a neighbor including lone/coincident-node fallback. Actor tests also cover deleting an edge from a target loop then consuming that part in a join: deletion normalization follows the surviving source identity, and the whole batch takes one exact undo/redo. Actor tests verify exact undo/redo and a batch that joins successfully then fails leaves bytes, selection and history unchanged. Actor-to-pinned-engine integration splits and rejoins Capsule to one generated part with the original triangle count, and extends its first endpoint into a four-node chain accepted by the engine.

Native manual evidence used isolated `org.dust3d.editor.qa` and a disposable Capsule copy:

- Selecting interior Node 2 disables Add Node while New Part stays enabled.
- Selecting endpoint Node 1 enables Add Node. It creates Node 4 at (0.5, 0, 1), radius 0.12, with edge Node 4 → Node 1 and a 96-triangle preview. One Undo restores three nodes and 80 triangles and exhausts undo.
- Disconnecting Node 1 → Node 2 produces 176 triangles. Node 2’s Connect menu offers Node 1 across parts; connecting restores 80 triangles. The menu help discloses the source-settings rule.
- One Undo of the join restores 176 triangles; one Redo restores 80. Save completes without an Edited marker.
- Independent saved-archive XML inspection confirms one part, one component with original color #468bcc, three original node IDs/coordinates/radii and two consistently directed edges. The new connecting edge receives a fresh UUID.
- Closing and reopening the saved file renders 80 triangles with empty selection and disabled Undo/Redo. The isolated QA app was quit normally; the user’s running editor/viewer and unsaved work were left alone.

No Qt GUI comparison, VoiceOver, oldest-supported-macOS, large-model performance or native UI exercise of every negative case is claimed. Loops, namespace cases and profile-cycle failures have automated coverage. This stage does not add clipboard, explicit edge picking, empty-part cleanup, arbitrary branching or complete M2/M3–M8 parity. The source-settings rule deliberately replaces consumed target settings; lossless preservation applies to unrelated data and exact snapshot undo, not to retaining both conflicting part styles in the resulting merged part.
