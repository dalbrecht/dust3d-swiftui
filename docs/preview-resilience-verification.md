# Editor preview resilience verification

`make ci` passes 157 tests, formatting, both native builds and Qt-free linkage checks. Document coverage remains 1596/1670 lines (95.57%); editor model is 735/741 (99.19%), pure editor state 338/338 and undo 92/92. The new MeshPreviewState has 31/31 covered lines. Inherited C++ coverage is not measured here.

Four regression tests were written before implementation; the initial run failed because MeshPreviewState did not exist. Tests cover initial failure/retry, stale output retention/recovery, obsolete success/failure and duplicate completion rejection, and clearing/invalidation. The app retains the existing 150 ms debounce and serialized core service.

Native QA used an isolated ad-hoc signed QA bundle on macOS, leaving the main editor/viewer and unsaved user work untouched:

- Opened a one-node document: 112 triangles, no history. Set radius to zero and applied: the document changed, core generation failed, and the original sphere remained rendered with “Showing last valid mesh”, the actual error and Retry Preview. Visually inspected the rendered window.
- Retried the failed generation: retained geometry and the warning remained. Saving succeeded; independent archive/XML inspection confirmed the saved node had radius zero despite the preview failure.
- Undo restored radius 0.12 and a current 112-triangle mesh without stale/error labels; Redo restored radius zero and the stale warning. Retry did not add an undo entry.
- Restored the valid state, deleted the only node, and observed an empty preview with no retained geometry. Undo regenerated the sphere. Restored and saved the disposable QA source.
- Opened a separate zero-radius document with no prior successful mesh. It displayed Preview unavailable and Retry Preview, without showing another window’s sphere. Retry left Undo/Redo disabled and did not dirty the document.
- Quit the QA app normally after restoring/saving its modified fixture.

Request-race behavior is checked by the pure state tests, not by nondeterministic UI timing. GPU device/allocation failures, VoiceOver, oldest-supported-macOS and generation latency budgets were not certified. This milestone changes no core dependency or C++ code and does not claim full M2 or later modeling parity.
