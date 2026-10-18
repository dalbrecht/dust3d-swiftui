# Native material viewport verification

Apple #131, local implementation; final full gate and native first-frame recheck pass.

## Automated acceptance

The focused 16-test suite passes locally: shared viewport adoption, camera changes
during uploads, fit/wireframe state, ordinary fallback, failed-revision retry,
cancellation, obsolete completion rejection and weak view lifetime; editor
material-only refresh, exact undo/archive preservation, optional failure/retry,
replacement/stop/empty lifecycles; exact bounded file snapshots; viewer fallback,
retrying the same bytes and rejecting results after replacement/stop.

Tests run against actual Metal when available, explicitly skipping GPU work only
when the device is unavailable. Existing production-encoder GPU tests remain
separate evidence for map shading and alpha behavior. Local rendered images are
not portable golden baselines.

## Native acceptance protocol

Launch the current editor and viewer under their reused bundle IDs. Open retained
.ds3 examples, inspect material adoption and map effects, exercise orbit/zoom/fit/
wireframe and optional diagnostics, then close normally. In the editor, edit
material values, undo/redo and save/reopen without losing retained archive data.
Supply a current app screenshot when the PR opens; clearly separate offscreen
renderer images. Do not ask an unavailable human to operate the app.

## Limits

Preview baking currently regenerates geometry and uses bounded preview map sizes;
this is not incremental bake caching, full-resolution export or a hard RSS cap.
Material generation is cooperative and cannot preempt every inherited phase.
Full M4/Qt parity and later editor milestones remain open in the port plan.

## Native checks and first-frame regression

The current editor opened a disposable Sword archive, applied blade Glow 2,
visibly changed shading, undid to 0 and redid to 2, and displayed wireframe,
orbit/zoom and fitted output. Save wrote the edited emissive value to the QA
archive; the standalone viewer subsequently opened and rendered that saved file.
No source fixture was edited. Stale material inspector copy was corrected.

Native QA caught that an async upload could leave the ordinary first frame until
a subsequent interaction. A failing presentation-request regression reproduced
zero draw requests after acceptance. The fix explicitly requests presentation on
paused MTKView after ownership transfer; all 21 targeted viewport, app lifecycle
and production GPU tests pass. The rebuilt viewer was reopened on the saved QA file, then captured without any
render-control interaction: the bright blade and material-lit guard appeared
automatically. The first-frame native regression check passes.

The earlier full gate passed 612 tests, formatting, build, coverage, Qt-link and
bundle rebuild checks. Measured coverage before the final presentation fix:
file service 37/37, viewer store 117/117, upload admission 88/88, editor store
750/861 and viewport 153/220 lines. Native UI coverage remains an explicit gap;
do not claim every application/UI file meets 95%. The final gate subsequently passed 613 tests (84.329 seconds), all formatting,
build, coverage, Qt-link and isolated bundle rebuild checks. Review and all
remote CI remain required before merge.
