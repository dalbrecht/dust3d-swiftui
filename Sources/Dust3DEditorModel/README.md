# Dust3D editor model

Swift 6 library for one document’s selection, validated node edits and undo/redo.
`EditorState` is a value-based state machine; `EditorSession` serializes it away
from the UI actor and returns immutable snapshots. Each window owns a session.
`CanvasProjection` maps Front X/Y and Side Z/Y gestures to model coordinates.

Use `try await session.open(data:)`, select a node ID, then `edit(id:position:radius:)`.
Open/edit failures retain the previous state. One edit call is one undo step;
selection does not dirty the archive. Parts marked hidden or locked are read-only.
History bounds and lossless archive preservation come from Dust3DDocument.

No SwiftUI, AppKit, Qt or additional package dependency. Run `make ci` at the repo
root; tests cover command atomicity, undo, locks, projection and actor routing.
