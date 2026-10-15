# Disconnected part splitting verification

`make ci` passes 101 tests, formatting, both native app builds, coverage gates and Qt-free checks. Measured line coverage is 922/950 (97.05%) for the document library and 526/532 (98.87%) for the editor model. Pure editor state remains 286/286 and undo history 92/92 (100%). This does not measure inherited C++ or native UI/GPU coverage.

Document tests cover deterministic largest-group/tie selection, fresh injected IDs, stale/invalid/colliding/overlong identity rejection, read-only sources, cycle handling, multiple groups, component-copy and part-count limits, copied-metadata size limits, default/explicit namespaces, comments, unknown part/component/edge fields, repeated/nested component references, child geometry retained only once, hierarchy insertion order, linked-profile identity stability, unreferenced/empty parts, binary assets and exact transactional undo/redo. Incompatible cross-part edges are rejected rather than silently regrouped.

Actor tests cover edge disconnection, direct/bulk node removal, mixed batches, only affected parts being normalized, no-op redo retention, failed-batch atomicity, selection and stable generated IDs on redo. Engine integration now depends on the existing local editor-model target so it exercises the actual actor preparation path; no external dependency was added. Both disconnecting a Capsule edge and deleting its middle node produce two-part models accepted by the exact pinned engine, and undo restores the original archive bytes.

Native manual evidence used the isolated `org.dust3d.editor.qa` app and disposable Capsule copy; the user's running editor and unsaved work were left alone:

- Disconnecting Node 1 → Node 2 generated a 176-triangle preview without a disconnected-part error. Node 2 selection stayed intact.
- Saving and independently inspecting XML confirmed two parts/components, one remaining edge, matching component colors, unchanged node IDs/coordinates, and the larger chain retaining its original part ID.
- One Undo restored the original 80-triangle chain and exhausted undo history.
- Deleting the middle node generated two remaining pieces with a 224-triangle preview. Removal plus partitioning took one Undo; Redo restored the same split.
- The completed two-node model saved and reopened with a 224-triangle preview and fresh transient selection/history.

No Qt GUI comparison, VoiceOver, oldest-supported-macOS or large-model performance certification is claimed. This fixes disconnected parts after removal; it does not implement cross-part joining, branching-chain support, empty-part cleanup or complete M2 parity. The current Connect menu still restricts targets to the same part. Metadata-copy budgeting is conservative near the model-size limit; future unknown schema semantics are not interpreted or remapped.
