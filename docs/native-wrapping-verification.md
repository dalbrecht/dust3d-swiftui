# Native wrapping inspector verification

Apple issue #102; ADR 0051. Exact core pin:
`2776de6933ae5f511e632afee6ffbd0c33dc0b75` (reviewed core PR #16).

The new tests initially failed to compile because the presentation/control types
were absent. Pure EditorModel tests now cover group-only availability, supported
and unknown modes, stable field identities, mode labels, titles and ranges.
Skin exposes only offset/smoothness; Cloth exposes the seven geometry fields.
None/unknown mode does not expose guessed defaults or apply hidden edits.

The actual component inspector and standalone wrapping controls are exported
through the existing hidden NSHostingView renderer at 250 points in light/dark.
Five source states yield twenty PNG artifacts: None, Skin, Cloth, unsupported mode
and unsupported values. Every render must preserve archive bytes, undo state and
publication count. The helper never orders a window front or appears in the Dock.
Artifacts are QA evidence, not committed or pixel-diff baselines.

Visual inspection found the original horizontal mode menu truncated unsupported
text. A vertical label/menu layout now keeps it fully readable. Inspected
representative light/dark images show complete native controls, visible ranges,
unsupported-value prompts and Apply/Reset buttons without clipping, including the
full Cloth component inspector. Artifacts are in /private/tmp/dust3d-wrapping-ui-qa.
Draft identity uses separate fields for document, component and mode; source/undo
changes reset local drafts without publishing a command.

Before the core pin update, SDK regressions failed for 24 zero-area midpoint
opening triangles and a fully collapsed far-origin model accepted without an
error. After the reviewed update, all twenty focused wrapping tests pass. SDK
checks require positive exported triangle area and precision-specific status 3,
which does not become successful-empty nil. Core's eighteen portable contracts
also check configured winding, connectivity and hem boundaries; these are not a
general topology guarantee or agreed Qt tolerance corpus.

Manual native pointer/keyboard, draft editing across selection/open/undo, GPU and
VoiceOver acceptance remain pending. Screenshots establish layout evidence only.
QA staging reuses the existing bundle identity and checks for running editor
processes before replacing a bundle that could have unsaved edits.

Full local `make ci` passed on 2026-10-17: 452 tests, formatting, native build,
coverage gates, both Qt-free app linkages and isolated bundle-rebuild regression.
Measured line coverage: mesh 73/74; document 2812/2896; model 1462/1468 (all 34 new
presentation lines covered); pure state 529/529; undo 97/97; orbit camera 33/33.
These Swift measurements do not establish inherited C++ coverage.

The canonical launcher staged the editor with --build-only after confirming no
Dust3DEditor process was running. The existing QA identity
org.dust3d.editor.combine-qa was reused in both bundle and ZIP, its placeholder
icon is present, and the ad-hoc signature verifies. The product app was not
launched; this confirms packaging only, not native interaction or GPU behavior.
