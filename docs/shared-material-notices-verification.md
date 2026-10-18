# Shared material preview notice verification

Apple #142 extends the editor correction from PR #141 to the standalone viewer
and Quick Look, without changing source archives, core pin or dependencies.

## Automated cases

- Known image-only and combined notices reflect actual baked/ordinary output.
  Actual legacy fields retain their limitation. Unreadable surface metadata has
  an explicit unverified state; unrelated engine messages remain unchanged.
- Immutable source capabilities preserve absent/present legacy metadata and the
  original typed parse/interpretation error. Unknown never means false.
- Real MeshFileService reads retain exact archive bytes and metadata together.
  A valid-UUID opaque component is accepted by the core while Swift's optional
  hierarchy interpretation rejects it; geometry still loads and the original
  DocumentError survives. This guards the best-effort boundary.
- Viewer request tests verify known, legacy and unavailable metadata, baked output,
  simulated original GPU failure, source cause display and stop/late-result safety.
- Quick Look document tests bake actual retained PNG input with/without legacy
  surface attributes, verify fallback warnings and original bake failure causes,
  and assert the source file is byte-identical after every read.
- Existing editor image workflow/history and real-bake tests remain part of the gate.
- Native open-panel observation exposed a forced 320-point SwiftUI minimum clipping
  the legacy notice in narrow columns. A layout regression first failed at 200/250
  points, then passes at 200/250/640 after host sizing and adaptive footer changes.

Before the review correction, `make ci` passed 683 tests with zero failures in 106.737 seconds, plus
build, strict formatting, Qt-free linkage and packaged app/extension rebuild checks.
Measured Swift lines: Kit 1454/1474; Document 3303/3391; EditorModel 1545/1551;
pure EditorState 534/534, Undo 97/97 and Orbit 33/33. These do not measure
inherited C++ core coverage. No supplied visual baseline exists; rendered
artifacts are not committed as one.

## Interface review

Typography and semantic secondary styling follow existing native notices; no new
layout system or custom chrome. Existing info-circle/warning symbols have text
labels. No new motion or hover-only controls. Capability parsing stays off-main;
notice selection is pure. Rejected hiding all warnings after a successful bake:
that would conceal real legacy and unknown limitations. Rejected a second archive
read in the viewer: it could attach capabilities from different source bytes.

## Native evidence, 2026-10-18

Rebuilt the standalone viewer and editor-owned preview extensions through the
canonical packaging script, reusing org.dust3d.viewer and the existing
org.dust3d.editor.quicklook/thumbnail identities and bundle paths. Closed the old
viewer/editor QA processes and retired old read-only provider workers before final
launch. Registration reports exactly one Quick Look provider at the canonical QA
path. Final viewer PID 87286 and provider PID 87409 started after staging completed;
source manifests and binary digests are retained in
`/private/tmp/dust3d-shared-notice-final-build-provenance.json` and process evidence
in `/private/tmp/dust3d-shared-notice-final-processes.txt`. These are current working
tree observations, not claims about an older process after a bundle was replaced.

Native viewer and macOS open-panel Quick Look both rendered the image-bearing
capsule without the obsolete image notice. Both showed the legacy-only notice for
the wrapPattern fixture and ordinary blue geometry plus the exact retained image
filename/PNG decoding cause for the malformed-image fixture. The viewer's native
picker initially delayed enabling Open after registration; it subsequently opened
all three cases without any filter/source workaround. Native system preview is
OS-hosted extension evidence, not an offscreen render or a Finder Space-bar rerun.

The initial narrow host clipped a fixed-width notice. After the responsive-layout
fix, a freshly started provider showed the complete two-line legacy notice, one
Wireframe checkbox, Fit button and wrapped mesh summary in the native preview
column. Wireframe toggled to on and Fit remained operable. The final rebuilt
viewer reopened the valid image fixture and rendered it without the old notice.
Screenshots were inspected and are supplied in the task. SHA-256 checks confirm
all three native fixture archives remained byte-identical after preview/open.

Verdict: shared policy, read-only/failure boundaries, native valid/legacy/invalid
states and final narrow-host readability pass. Native appearance evidence is dark
mode. Full VoiceOver, keyboard-only navigation, actual forced GPU failure, light
appearance and renewed Finder Space-bar acceptance are not established by these
checks. Pure/layout tests do not establish full native accessibility or M4 parity.

## Automated review correction: GPU readiness

CPU bake completion no longer clears or downgrades the notice. Viewer, editor and
Quick Look require a successful Metal command completion from the current material
renderer. View/revision guards reject detached or obsolete callbacks, and material
replacement clears readiness. The regression tests first reproduced premature
warning removal in the viewer and Quick Look; renderer tests distinguish resource
upload from frame completion and reject a detached renderer callback. The full corrected `make ci` passes 683 tests in 137.887 seconds with zero failures,
plus build, formatting, coverage and Qt-free/package checks. Coverage measurements
remain as recorded above.

Freshly staged viewer PID 70891 and canonical Quick Look provider PID 72478 were
started after the correction build. OS open-panel Quick Look rendered the retained
image fixture without the obsolete image notice and retained the fully wrapped
legacy-only notice for the legacy fixture. These observations verify the final
rendered states; the upload interval itself is covered by deterministic regression
tests rather than a timing-sensitive screenshot. The current Open panel has kept
its Open button disabled, so a new standalone viewer document-load check has not
yet been established for this correction.
