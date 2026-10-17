# Editor preview session verification

Apple issue #110; ADR 0055. The editor consumes the reviewed session SDK from
PR #109. The dependency pin remains d691a7feb1718874b3cef0d9c843af961a252b42;
no native adapter, dependency or CI configuration is added here.

## Contracts and regressions

The initial service/store tests failed at the missing integration interface.
Eleven new tests now exercise real cache reuse and scope replacement; obsolete
reset protection; primary error preservation and cache-only degradation;
pre-cancellation; stopped/obsolete result rejection; retry reuse; empty-document
cleanup; preserved document bytes/publication; last-valid mesh on genuine failure;
and recovery that separates cache warnings from primary errors.

Suspended preview services resolve old requests after newer requests or stop.
Tests await the captured generation task, rather than assuming a sleep/yield has
drained a completion. Real SDK/core tests prove actual reuse, not just fake output.

A controlled asynchronous backend reproduced 12 overlapping service calls
across concurrent replacement scopes before the serial operation tail. The
regression now observes a maximum of one. Native engine serialization already
existed; this preserves per-editor job ordering across SDK actor awaits and
avoids additional blocked jobs from that editor.

A suspended backend also proves cancellation reaches the queued operation:
temporarily removing the relay makes the regression fail, and restoring it makes
the full gate pass. This does not claim to interrupt native generation in progress.
Backend protocols are ordinary dependency boundaries; no production failure
switches or native fault-injection hooks are introduced.

## Gate and coverage

Full make ci passes: 489 tests, two explicit no-Metal-device skips, no failures.
Formatting, warnings-as-errors build, coverage, both Qt-free app linkages and
bundle rebuild/archive isolation checks pass. The two existing skipped tests are
the production indexed/expanded Metal comparison and later-revision viewport
recovery; no new GPU pass is claimed in this environment.

The new preview service measures 69/69 lines and the cache notice 20/20. The
whole existing EditorStore measures 646/757 lines (85.34%); this is not a claim of
95% coverage for the entire application shell. Mesh SDK remains 268/273, document
2812/2896, editor model 1462/1468, pure editor state 529/529, undo 97/97 and orbit
camera 33/33. Swift reports do not measure inherited C++ coverage.

## Rendered evidence and limits

The production cache notice was rendered offscreen at the preview column width
in light/dark appearances with short/long diagnostics. All four PNGs were visually
inspected: readable semantic foregrounds and wrapped complete messages without
clipping. The helper prohibits application activation and visible windows.
No app was launched, no new QA bundle ID created and no human button press used.
No reference design was supplied; no pixel baseline is invented or committed.

The notice remains separate from generation/render errors. Editing, undo/history
and saving do not depend on cache success; diagnostics and statistics are transient.
Root document identity remains stable during edits, so ordinary publication does
not reload/reset the cache. Encoded documents already store immutable Data; this
stage does not move or benchmark archive encoding.

Cancellation remains cooperative. Cleanup errors are best-effort and preserve
their cause in privacy-protected logging without modifying a stopped UI. Native
GPU/window/VoiceOver acceptance and controlled resource/performance budgets remain
separate gates. Source provenance, Qt differential acceptance and full M3/editor
parity remain incomplete.
