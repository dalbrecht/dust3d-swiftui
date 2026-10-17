# Native part deformation controls

Issue #87 adds Width scale and Thickness scale drafts, each with Apply/Return
and Reset Draft, plus Unified deformation. The controls forward to the existing
reviewed store commands; no new mutation path, dependency or core revision is added.
Inputs accept the existing bounded 0 through 2 engine-compatible numeric parser.
Unsupported source values remain empty/explicitly unsupported until replacement.
Reset Draft restores the source interpretation without publishing an edit.
Drafts reset when part identity or the corresponding source value changes.

## Evidence

The new render test first failed because PartDeformationControls did not exist.
The renderer then exposed that unsupported numeric text prevents preview generation
with the original core `stod: no conversion` diagnostic; tests now explicitly
expect that state instead of claiming a valid preview. Known fixtures generate.
Four rendering tests pass: actual inspector and isolated controls, known and
unsupported states, light/dark appearances, valid PNG output, unchanged archive
bytes and no undo history created. Actual inspector width is 250 points.

Inspected transient artifacts under /private/tmp/dust3d-deformation-ui-qa-final
show persistent scale labels, 0.995/1.25 drafts, explicit unsupported guidance,
full-width replacement menu and readable action buttons without clipping.
These are inspection artifacts, not committed snapshot baselines.

Full `make ci` passed on 2026-10-17: 392 tests, zero failures, formatting, native builds, coverage reporting, Qt-free checks and isolated signed bundle-rebuild regression. Existing command-layer geometry, validation, undo/redo
and lossless save evidence is recorded in part-deformation-verification.md.

## Remaining acceptance

Inactive offscreen rendering does not establish keyboard/pointer operation,
selection/draft transitions, VoiceOver, native Save/Undo/Redo menus or Metal/GPU
rendering. Those checks remain pending without human input; no app launch or
new application identity was required. Reuse org.dust3d.editor.combine-qa for
future native checks. Cut-face controls, other M3 modifiers and differential
Qt acceptance remain pending. This is not a full modeling parity claim.
