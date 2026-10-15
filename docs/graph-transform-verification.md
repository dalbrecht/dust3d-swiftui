# Edge reversal and selection transform verification

`make ci` passed 87 tests, formatting, both native app builds, coverage gates and Qt-free linkage checks. Measured line coverage: document library 666/682 (97.65%), editor model 439/445 (98.65%), pure editor state 286/286 and undo 92/92 (both 100%). Inherited C++ and native GPU/UI remain separate verification scopes.

New tests verify each of the eight transform results against explicit coordinates, editable-centroid/read-only behavior, interaction locks and the Qt X/Z exception, unchanged radii/assets, exact undo/redo, empty/read-only/single selections, invalid geometry and locked provisional overflow, bulk edge validation, unknown edge attributes/children, exact net-zero double reversal, selection reversal and actor methods. A real Capsule chain reversed through the new command remains readable by the exact pinned engine with the same triangle count; undo restores its original bytes.

Native manual QA used isolated `org.dust3d.editor.qa` and a disposable Capsule file. The user's running editor and unsaved document were left alone:

- The inspector transform menu exposes all eight actions. Front clockwise rotation moved the vertical chain to horizontal, updated the mesh, and saved X coordinates .25/.5/.75 with Y=.5 and unchanged Z.
- Fit reframed the rotated canvas and mesh.
- Reverse Selected Edges reversed both chain edges; saved XML was inspected independently.
- A single-node inspector showed “Edge from Node 2 to Node 1”; Reverse Direction changed it to “Node 1 to Node 2”. Undo restored direction.
- Separate undo steps reversed the single-edge action, group reversal and rotation. The original node coordinates and exhausted undo state were verified.
- A synthetic cross-part edge fixture verified that an inspected editable node retains its editable edge menu while the edge to a locked endpoint is disabled. The pinned engine explicitly rejected this fixture for incompatible edge endpoints; this check demonstrates UI availability only, not engine interoperability. Locked and hidden endpoint variants are covered by model tests.
- X/Z exchange changed X=.5/Z=1 to X=1/Z=.5 while both axis locks remained enabled; the menu explicitly discloses the exception. Undo restored geometry and retained locks.

All transform math is automated, but each flip/side-rotation menu item has not been separately exercised by pointer. No Qt GUI comparison, VoiceOver, oldest-supported-macOS, or large-model performance certification is claimed. Clipboard, explicit edge selection, descendant-pivot rotation, alignment, reference images and graph split/merge remain pending.
