# Dust3D Editor

Separate macOS 14+ SwiftUI document app. Run from the repository root with
`./script/build_and_run.sh --editor`, or package with `--editor --build-only`.

Open an existing `.ds3`, select a node in the list or canvas, drag it in Front
(X/Y) or Side (Z/Y), or edit X/Y/Z/radius and press Apply. Undo/redo operates on
committed edits. Native document scenes provide Open, Save, Save As and unsaved
close handling. Each window has independent state. Locked/hidden parts cannot
be changed. The mesh preview uses the same Qt-free engine and Metal renderer as
the standalone viewer.

New documents start empty. Use the + menu to Add Node (extend the selected node
in the same part) or New Part. Connect to… and Disconnect edit edges in the
selected node’s inspector. Delete Node removes its incident edges in one undo
step. Part locks and visibility are enforced. Connecting different parts and
duplicate/self edges is rejected. Full modeling inspectors remain later milestones. Unsupported mesh assets remain preserved
even when the preview cannot display them. The standalone viewer remains read-only.

Development: `make ci`. No Qt dependency, hand-maintained Xcode project or extra
Swift package is required beyond the existing pinned engine dependency.

Quit the editor normally before using the run script again; it refuses to kill a
running editor with potentially unsaved document edits. `--build-only` does not launch.
