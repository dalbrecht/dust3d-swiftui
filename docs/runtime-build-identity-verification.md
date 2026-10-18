# Runtime build identity verification

Apple #136 adds runtime provenance for controlled native acceptance. It does not
establish modeling/Qt parity, close #120, or complete M8.

## Automated evidence

- Metadata decoding rejects missing/invalid schema, malformed revisions and oversized
  input while preserving typed original causes. Captured values are immutable.
- Pure presentation distinguishes source/core/digest and runtime rows and does not
  fabricate source identity after decoding failure.
- Isolated Git fixtures verify clean deterministic metadata, distinct dirty edits,
  untracked/deleted/ignored inputs, and explicit missing Git/core-pin failures.
- Exact process matching handles spaces and /tmp aliases without matching another
  app with the same executable basename. Expected-running verification uses the
  same exact-path logic.
- A disposable macOS process compiles the production loaded-image reader, reports
  identity A, retains A after its executable is atomically replaced, and reports B
  after a controlled restart. No user document or native app bundle is overwritten.
- The packaging regression reuses org.dust3d.editor.combine-qa, checks its signature
  and confirms copied Quick Look/thumbnail providers are removed. Canonical packages
  retain their providers and default archives remain unchanged.

## Native evidence and limits

The existing QA editor PID 49790 was quit normally before staging. The first fresh
process PID 66763 showed the source revision, dirty state, content digest, exact
core pin, QA bundle ID and capture timestamp from its loaded executable. The
running-app guard refused to rebuild that exact bundle. Native inspection exposed
that visible rows were absent from the accessibility tree; explicit labels/values
were added before final inspection. The first process was quit normally afterward.

Final `make ci` passes 690 Swift tests with zero failures in 114.990 seconds,
plus nine build-support tests, builds, strict formatting, coverage, Qt-free linkage
and signed canonical/QA package rebuild checks. Measured lines remain Kit
1454/1474, Document 3303/3391, EditorModel 1545/1551, pure EditorState 534/534,
Undo 97/97 and Orbit 33/33. These are not an inherited C++ coverage measurement.

Corrected QA process PID 71678 started at 2026-10-18T15:39:55Z after staging.
Native screenshot and accessibility inspection show all six identity rows with
explicit labels, values and identifiers, including QA bundle identity. Source
revision was a87f606e0c583161d3565d637f713678da3bb0d8 with modified-source status
and digest e1ed56135b38b78ba4ea0f32a592f418da775014095cf5e35f78e46485af3731;
core revision was 2703a17ce4c1f8d21a30b23580b45520ef49c87b. These are the actual
pre-commit QA capture, not a claim about the eventual PR commit. Process evidence
is retained in `/private/tmp/dust3d-runtime-build-identity-native-process.txt`.
The process was quit normally before the subsequent clean-revision build.

The About window is readable in the native dark appearance. Cmd-W closed its
window but the helper timed out while observing the remaining app; that result
does not establish complete keyboard navigation or VoiceOver acceptance. Startup
logging is implemented; persisted log output was unavailable in this inspection.
The process-replacement integration test establishes loaded-image lifetime behavior;
a native app with unsaved documents is never deliberately overwritten to test it.
Full VoiceOver, light-mode inspection, release signing and complete modeling
acceptance remain outside this evidence. No inherited core coverage claim is made.

## Automated review correction: resolve before identity capture

Review found that generating metadata before SwiftPM resolution could embed an old
core revision after a manifest dependency update. Two failing orchestration tests
reproduced stale capture and ignored resolver failure. The wrapper now resolves
with the configured scratch/cache paths before hashing sources and embedding the
resolved core pin. Both regressions and the real package’s seven focused identity
tests pass. The full corrected `make ci` passes 690 Swift tests in 119.779 seconds
with zero failures and 11 build-support tests, plus formatting/build/coverage,
Qt-free and signed canonical/QA package checks. Exact-head automated review and
remote CI remain required. Earlier
native captures above predate this build-order correction; the app reader and
diagnostics presentation are unchanged.

## Automated review correction: post-build process recheck

Review identified a stale pre-build guard when a target launches during a long
compilation. Three orchestration regressions first reproduced replacement of the
original executable in viewer, canonical editor and QA editor build-only modes.
The script now rechecks the same exact target immediately before the first bundle
mutation. All three tests retain the original binary bytes and reject packaging
with the original running-target diagnostic. The corrected full `make ci` passes
690 Swift tests in 126.652 seconds with zero failures, 14 build-support tests,
formatting/build/coverage, Qt-free linkage and signed canonical/QA package checks.
Fresh exact-head review and remote CI remain required. This is a recheck
at the mutation boundary, not a cross-process launch lock.

## Automated review correction: QA names and log scope

Review found canonical naming in the QA About UI and process-name-based log
filtering that could mix canonical/QA events. The menu, title and header now select
the QA name from the immutable captured bundle identity; unknown identities keep
the caller’s fallback name. Both log modes filter the selected app’s distinct
subsystem. Failing naming tests and real script-dispatch tests reproduced these
issues before the fixes. Native side-effect executables are stubbed in the latter
tests, so they never launch UI or start a system log stream. The full corrected
`make ci` passes 692 Swift tests with zero failures in 104.027 seconds, 17
build-support tests and all formatting/build/coverage, Qt-free and signed package
checks. Native QA PID 21114, captured at 2026-10-18T16:25:31Z, shows “Dust3D Editor
QA” in the menu, window title and diagnostics header, with all identity rows still
accessible. Its pre-commit source capture reports modified revision
88393777921c38728bc5d44e3076b8912753607b and digest
1c4599bcd97b499671b17f0c865880f04fc0c20073688bc614f3258602bbe62c.
Fresh exact-head review and remote CI remain required.

## Automated review correction: preview-cache event routing

Review found that the preview-cache reset logger still used the canonical
subsystem, so a QA-only stream omitted those events. Preview-cache, recovery and
startup loggers now use one pure captured-identity scope selector, including an
explicit fallback for launches without a bundle ID. Tests distinguish QA and
canonical scopes and preserve custom/missing identity behavior. Focused identity
and preview-store tests pass; no native cache-reset failure was forced in this
pass. The corrected full `make ci` passes 694 Swift tests with zero failures in
139.558 seconds, 17 build-support tests and all build/formatting/coverage, Qt-free
and signed package checks. Fresh exact-head review and remote CI remain required.

## Automated review correction: provider compilation preflight

Review found two provider builds inside the packaging helper after the final
process check. The canonical entry point now compiles the app, Quick Look and
thumbnail products before that check and before any bundle mutation. The helper
requires prebuilt binaries/resources, never compiles, and rechecks the owning
editor before each provider copy. Four failing regressions reproduced target
launches during either provider build and either build failing after the app had
already been replaced. All now retain the original executable and metadata.
The corrected full `make ci` passes 694 Swift tests with zero failures in 131.052
seconds, 21 build-support tests and all build/formatting/coverage, Qt-free and
signed canonical/QA package checks. Fresh exact-head review and remote CI remain
required.
