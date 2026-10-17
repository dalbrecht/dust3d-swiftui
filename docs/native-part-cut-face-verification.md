# Native cut-face controls verification

Issue #89 adds a built-in preset menu, searchable linked-profile choices and
rotation drafts to the real part inspector. Existing reviewed commands provide
validation, exact undo/redo, lossless archive edits and regenerated previews
(see part-cut-face-verification.md). No dependency or core revision changes.

The new render test first failed because PartCutFaceControls did not exist.
Known presets, unsupported source metadata, unresolved exact linked IDs and
resolved links now render without rewriting archive bytes or creating history.
Additional fixtures cover an empty chooser and duplicate long Unicode names
with distinct IDs. The chooser excludes self and uses bounded lazy rows.
Cycle/missing-target rejection remains in the existing atomic command path.

The final render command is `./script/render_editor_ui_qa.sh
/private/tmp/dust3d-cut-face-ui-qa-final`. Six rendering tests pass. Images are
transient inspection artifacts, not committed pixel baselines. Actual inspector
width is 250 points. Inspected light/dark artifacts show readable labels, full
unsupported guidance, wrapped unresolved IDs and unclipped actions. Long chooser
labels are intentionally truncated with full details in help/accessibility labels.

Full `make ci` passed on 2026-10-17: 394 tests, zero failures, formatting,
native builds, coverage reporting, Qt-free checks and isolated signed
bundle-rebuild regression. Measured lines remain document 2531/2615, editor
model 1394/1400, pure editor state 523/523, undo 97/97 and mesh 66/67; these
figures do not measure native UI or Metal coverage.

## Remaining acceptance

Inactive offscreen rendering does not establish pointer/keyboard operation,
search/menu transitions, native Save/Undo/Redo, VoiceOver or Metal/GPU rendering.
These remain pending without desktop input. No new app identity or product
launch is needed for the artifact exporter. Future native checks must reuse
org.dust3d.editor.combine-qa. Target roles, other M3 modifier families and Qt
differential profile acceptance remain incomplete; full parity is not claimed.
