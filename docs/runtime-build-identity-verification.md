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
