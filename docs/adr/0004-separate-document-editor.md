# ADR 0004: Separate native document editor

Status: accepted, October 14, 2026.

## Decision

Keep Dust3DViewer read-only and add Dust3DEditor with its own executable, bundle
identifier and packaging option. Share Dust3DRendering for Metal, rather than
copying the viewer renderer. Keep the exact external engine pin unchanged.

Use SwiftUI DocumentGroup/FileDocument for native open, save, Save As, dirty
state, file coordination and document windows. FileDocument stores archive bytes;
XML semantics and lossless patches remain in Dust3DDocument. A scene owns an
observable main-actor store and a separate EditorSession actor. Only committed
archive changes update the file binding. Selection/camera state never enters the
archive. EditorState validates candidate state before publishing it.

One drag commits once on release; inspector Apply commits all fields together.
The custom command group routes undo/redo through the focused scene, sharing
exactly the same bounded history as the toolbar. Text-field draft editing remains
local until Apply. Geometry generation is derived, debounced, serialized through
the existing engine gate and guarded against stale revisions. Preview failure
must not roll back or prevent a valid save.

Use an HStack pane shell with a native List sidebar, canvas, preview and optional
inspector. Nested SwiftUI split/inspector containers produced a repeatable native
constraint-update exception when opening document windows on this development
OS. Both new and existing documents were retested after removing those split
containers. Pane resizing is deferred; introducing a split layout again requires
runtime document-open regression verification, not merely a successful build.

## Consequences

Pure model tests run without a window or GPU. Native file menus and Metal still
require explicit manual checks. Existing-node edits are the first vertical slice;
new topology, individual axis locks, rich inspectors, autosave/recovery evidence,
3D picking and complete Qt parity remain later milestones. Unknown archive data
continues to survive saves through the existing lossless document implementation.
