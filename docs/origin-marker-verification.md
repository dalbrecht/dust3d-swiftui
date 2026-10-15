# Origin marker verification

Full `make ci` passes 224 tests, formatting, both native builds, coverage and Qt-free linkage checks. Document coverage remains 1852/1927 (96.11%), model 889/895 (99.33%), pure editor state 415/415 and undo 97/97 (100%). This is not inherited C++ coverage.

Two new projection tests first failed against the absent origin-bounds API. They now cover positive/negative/boundary origins, both projections, node/reference/origin union, empty scenes, invalid origins and hidden-node exclusion. A controller regression verifies that outlying origin edits, Undo and Redo keep the origin inside both canvas projections without resetting the mesh camera; explicit Fit still resets that camera and does not mutate the document. Existing movement/visibility regressions remain green.

Native QA used a separately staged app:

1. Opened the asset-bearing diagonal capsule. The Origin scope/label appeared at the middle node; accessibility exposed its X/Y/Z values. A coordinate click at the overlapping node center selected Node 2, confirming the marker did not intercept picking.
2. Edited origin to (5,-4,7) through the existing inspector. Front and Side fitted both the marker and graph without a manual Fit. The native preview remained available with 80 triangles.
3. Undid the origin edit and saved after switching projection. Whole-file comparison with the original archive was identical, including all opaque assets/metadata.
4. Inspected a blank document and moved its help below the marker to avoid crowding. Native scope coordinates use complete numeric strings instead of fixed six-decimal interpolation.

Original user apps and unsaved work were untouched. No marker dragging, automatic settlement, VoiceOver certification or full M2 parity is claimed. See [the decision](adr/0021-origin-marker-and-fit.md).
