# ADR 0006: Transient multi-node selection and bulk graph edits

Status: Accepted for the editor prototype.

Each window's editor model owns a set of selected node IDs. Selection is transient, excluded from archive bytes and undo records, and validated atomically. Nodes remain ordered by document order; the first selected node is the deterministic primary node for single-node actions. Publishing document edits removes IDs that no longer exist. Undo restores document data but does not resurrect a deleted selection.

Dragging a selected node translates the editable nodes in its group. Dragging an unselected node selects and moves only that node. Read-only nodes can be selected for inspection but are excluded from group movement and deletion. Interaction locks apply to each moved node. A group inspector accepts relative offsets, preserving distances between editable nodes; it does not apply one absolute position to every node.

Bulk geometry and deletion commands mutate and serialize model XML once per operation. They validate the whole request before publishing a replacement archive, preserve unrelated XML and archive assets, and record one undo snapshot. Bulk geometry transactions compare canonical model XML for net-zero detection, avoiding repeated per-node archive parsing. No new dependency or native core API is needed.

Native sidebar selection supplies Command/Shift behavior. Canvas Command-click toggles a node. Canvas Select All Nodes uses Command-Shift-A so text controls keep their standard Command-A behavior. Canvas drag previews move all participating handles and edges in a stable named coordinate space; the actor commits the model once when the drag ends.

This stage does not implement marquee selection, edge selection, scaling, clipboard UUID remapping, or Qt's part splitting/merging behavior. These remain explicit M2 work in the full port plan.
