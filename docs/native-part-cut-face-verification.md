# Native cut-face controls verification

Issue #89 adds a built-in preset menu, searchable linked-profile choices and
rotation drafts to the real part inspector. Existing reviewed commands provide
validation, exact undo/redo, lossless archive edits and regenerated previews
(see part-cut-face-verification.md). No dependency or core revision changes.

The new render test first failed because PartCutFaceControls did not exist.
Known presets, unsupported source metadata, unresolved exact linked IDs and
resolved links now render without rewriting archive bytes or creating history.
Additional fixtures cover an empty chooser and duplicate long Unicode names
with distinct IDs. The chooser excludes self and unlinkable legacy identities and uses bounded lazy rows.
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

## Automated review regression

The first review identified that a legacy non-UUID part could be offered as an
enabled profile choice even though the command always rejects it. Two regression
tests first failed without the new compatibility projection. The document layer
now exposes its existing profile-identity classification through
`canBeCutFaceProfile`; the pure `PartProfileOptions` projection excludes such
parts and self without rewriting them. Tests retain braced uppercase and
unbraced exact IDs, duplicate Unicode titles, source ordering, case-insensitive
name/ID searches, empty results and byte-identical legacy preservation. The UI
uses that tested projection. Fresh full-gate results follow the initial record.

The review fix passes fresh full `make ci`: 396 tests, zero failures, formatting,
builds, Qt-free and bundle checks. Measured document lines are 2532/2616 and
editor model 1409/1415; pure editor state remains 523/523 and undo 97/97.

A fresh review found that the menu still offered an inert unsupported option
for known profiles. Three new regression tests first failed without the menu
projection. `PartCutFaceOptions` now supplies presets and the exact current
linked value, adding nil only for an unsupported source. The view disables that
read-only placeholder. Tests cover every preset, exact/unresolved linked IDs,
unique choices and explicit replacement options. Fresh full-gate results follow.

The menu fix passes fresh full `make ci`: 399 tests, zero failures, formatting,
builds, Qt-free and bundle checks. Editor model lines are 1416/1422; document
2532/2616, pure state 523/523 and undo 97/97 remain unchanged. Re-rendered
known, unsupported and unresolved controls in light/dark appearances under
/private/tmp/dust3d-cut-face-menu-review-qa were inspected: source placeholders
remain readable and supported profiles display their chosen value. Native menu
interaction remains pending rather than inferred from static render output.
