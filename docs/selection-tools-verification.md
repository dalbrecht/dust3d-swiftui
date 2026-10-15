# Marquee and scaling verification

`make ci` passes 80 tests, both native builds, formatting, Qt-free source/link checks and coverage gates. Measured editor model line coverage is 353/359 (98.33%), including 224/224 pure editor state lines (100%); undo remains 92/92 (100%). Document library remains 641/656 (97.71%). These figures do not describe inherited C++ or GPU/UI coverage.

Seven new tests cover visible-center marquee selection in Front/Side planes, forward/reverse/mixed rectangle directions, exact boundary centers, hidden versus read-only nodes, invalid rectangles, centroid scaling, independent radius scaling, every lock combination, one-step exact undo/redo, opaque assets, invalid/nonfinite/nonpositive/out-of-bounds factors, empty/read-only/single selections, actor calls, byte-exact identity scaling with non-binary coordinates, and overflowing provisional values in locked fields.

Native checks used isolated `org.dust3d.editor.qa` with a disposable Capsule copy; the user's editor and unsaved document were left alone:

- Forward and reverse background marquee selected the two centers inside its bounds, replacing the prior selection without creating undo history.
- Side-plane marquee selected the expected nodes; empty-background click cleared selection.
- Group position factor 2 and radius factor 1.5 produced saved Y coordinates .25/.375/.875 and radii .12/.24/.18. Saved XML was inspected independently. The unselected node stayed unchanged.
- One Undo reversed the whole scale; Redo reapplied it and updated the mesh.
- A negative factor was rejected without adding history; one Undo still reversed the original scale.
- Automated review regression: entered a position factor of one billion, locked XYZ, and scaled radii successfully; saved XML retained all coordinates. Then entered a radius factor of one billion, locked radius, and scaled positions successfully.

The UI automation API rejects modifier-only key holds and has no drag-with-modifier argument, so additive Shift-drag was not manually verified. The rectangle/projection logic is tested, but modifier routing remains a manual check. No Qt GUI, VoiceOver, older-macOS, or large-model performance certification is claimed.
