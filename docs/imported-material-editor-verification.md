# Imported material editor verification

Tracked by #159; decision ADR 0075. This stage adopts the reviewed imported
renderer in the editor and does not complete M4 or the full editor plan.

## Automated evidence

Four new tests use the real synthetic `ImportedSurface.ds3` archive and substitute
only the async material boundary for race/failure cases. They cover current-frame
loading/notice acknowledgment; obsolete frame/error callbacks; replacement,
stop/empty output; original JPEG failure and exact-snapshot retry; actual node
movement, undo/redo and reopen with unchanged GLB asset bytes. The existing four
baked-material tests pass alongside these. The wider editor target passes 143 tests.

Full `make ci` passes: 31 build-support tests, 771 XCTest cases, formatting,
coverage gates, Qt-free linkage and isolated app/provider rebuild checks. Measured
lines: Kit 2073/2100, document 3471/3559, editor model 1545/1551, pure editor state
534/534, undo domain 97/97 and orbit camera 33/33. The broad AppKit-facing EditorStore
measures 927/1042 lines (88.96%); this is reported separately, not claimed to meet a
95% UI-boundary target. Wider controller/native coverage remains acceptance work.
Shared sampler, factor, alpha, sidedness, texture/mip and camera/wireframe behavior
retain ADR 0074's numerical and actual Metal tests. No whole-engine/GPU coverage,
Qt pixel parity, rendered file-preview or export claim is made.

## Native acceptance

Staged with `DUST3D_APP_OUTPUT_DIR=/private/tmp/dust3d-combine-qa
./script/build_and_run.sh --editor-qa --build-only`, reusing
`org.dust3d.editor.combine-qa` without preview providers. Native computer-use tools
opened a disposable copy of `ImportedSurface.ds3`, inspected the actual masked
material and current warning removal, selected Node 1, set X to 0.6 and radius to
0.2, and applied. The mesh changed while retaining materials. Command-Z restored
X 0.5/radius 0.15; Command-Shift-Z reapplied; Save cleared the edited marker.

Independent DS3 envelope/XML inspection of the natively saved file verified those
values and the original GLB SHA256
`d028b1f7680d65f8e03fd3db7fce8aa923d15b6fccf91d93d8559a59dd5f3c88`.
Closing/reopening restored X/radius with no undo history. Native wireframe,
orbit and zoom were inspected. A disposable broken-PNG archive retained geometry,
reported the original supported-PNG diagnostic, retained the imported limitation,
and exposed enabled Retry Materials plus editable node fields. Retry retained the
same diagnostic. Both QA documents were saved or unchanged before quitting.
Source fixtures and user documents were not edited.

Screenshots were inspected inline in dark appearance; the PR-open screenshot is
captured after the committed-identity rebuild. Native loading-race timing is
covered by deterministic store/viewport tests rather than a manual timing claim.
Broader VoiceOver, light appearance and performance acceptance remain open.

## Interface review (full mode, editor material adoption)

Uses existing SwiftUI/AppKit controls, semantic colors, SF Symbols and status/error
layout; no new theme, dependency or custom motion.

| Category | Evidence | Result |
| --- | --- | --- |
| Typography | Native inspector, status and original-cause notice | Existing system hierarchy retained; saved numeric values inspected |
| Surfaces | Loaded, edited/reopened and failed-material states | Existing preview/notice surfaces retained; controls remain usable |
| Icons | Toolbar, node selection and warning | Existing SF Symbols retained; no second icon system |
| Animations | Source and deterministic revision tests | No added animation; routine generation remains immediate system progress |
| Performance | Shared actor preparation/upload and immutable byte snapshot | Heavy preparation stays off-main; hard RSS/latency targets remain M8 |

| Severity | Before | After | Why |
| --- | --- | --- | --- |
| MEDIUM | Loading ended before current material presentation | Progress includes the current GPU frame | The displayed completion matches the visible result |
| MEDIUM | GPU errors directly changed current store state | Errors require the current viewport revision | Old callbacks cannot clear a newer document's materials |

Rejected: custom material-panel chrome would duplicate established controls;
animated mesh entrances would repeat on every edit; removing all warnings would
hide unsupported component/legacy features. Verdict: **Approve for this editor
stage**, subject to exact-head automated review and all hosted checks. Full M4 and
production parity remain unproven.
