# Native part modifier controls verification

Tracks #85 and #62. Decision: [ADR 0043](adr/0043-native-part-modifiers-and-render-qa.md).

## Functional and rendering evidence

The reviewed document/controller foundation already exercises each shape flag,
all sixteen shape combinations, a hard-join seam, finite/unit-normal actual core
meshes, unchanged camera/selection, semantic no-ops and exact archive/mesh history.
This stage exposes those commands in the native inspector without adding another
mutation path. Unsupported fields use explicit On/Off choices rather than an
implicit default; rendering must preserve their bytes and undo state.

New rendering tests first failed because the modifier view was absent. Three
contracts now render the actual inspector with known/unsupported source flags in
both appearances at the production width of 250 points, render the isolated
modifier section, reject invalid raster sizes before window creation, decode the
PNG output and verify exact document bytes and empty undo history. The test-owned
window stays hidden and is closed after capture; the artifact-exporting process
uses prohibited activation policy, with no product bundle launch or new app ID.

Inspected all four complete inspector images. Initial unsupported menus truncated
their selected values. The final layout stacks persistent property labels above
full-width menus; all five selected values are readable in both appearances.
Known toggle states, actual part names and guidance are visible without clipping.
New guidance uses the semantic primary foreground. Native text fields render
through AppKit; a pure ImageRenderer prototype instead showed unsupported-field
placeholders and was not used for inspector acceptance.

Repeat with `./script/render_editor_ui_qa.sh /private/tmp/dust3d-editor-ui-qa`.
Artifacts are named `part-inspector-known-light.png`, `part-inspector-known-dark.png`,
`part-inspector-unsupported-light.png`, `part-inspector-unsupported-dark.png` and
`part-modifier-section.png`. These are transient inspection artifacts; the tests
verify artifact validity and state preservation, not pixel parity.

Full `make ci` passed on 2026-10-17: 391 tests with zero failures, formatting,
native builds, coverage, Qt-free linkage and isolated signed bundle-rebuild
checks. Measured line coverage remains document 2531/2615, editor model
1394/1400, pure editor state 523/523, undo domain 97/97, orbit camera 33/33
and mesh library 66/67. These totals do not measure native UI/Metal coverage.

## Remaining native acceptance

This is an inactive, offscreen drawing context. Pointer/keyboard interaction,
unknown-menu choice transitions, native Save/Undo/Redo via menus, VoiceOver and
GPU rendering remain pending while the QA desktop is unavailable. Existing
controller/archive tests do not replace those end-to-end checks. Reuse
`/private/tmp/dust3d-combine-qa/Dust3DEditor.app` with
`org.dust3d.editor.combine-qa` when available. Deformation controls now have [separate offscreen verification](native-part-deformation-verification.md). Cut-face controls now have [separate offscreen verification](native-part-cut-face-verification.md).
Qt differential checks and the rest of M3 remain pending; full modeling
parity and native UI coverage are not claimed.
