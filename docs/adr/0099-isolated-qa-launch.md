# ADR 0099: Isolated explicit-fixture QA launch

Status: Implemented launcher; native acceptance pending (#257).

Unattended editor checks need an explicit owned fixture and deterministic startup
without deleting user restoration data, changing the normal editor lifecycle or
creating another bundle identity. Use a dedicated Python standard-library launcher
for the existing QA identity. Keep packaging and the ordinary launch path unchanged.

The helper validates absolute bounded paths, a regular `.ds3` fixture, QA bundle
metadata and the expected executable before issuing one argument-vector Launch
Services command. The caller remains responsible for fixture ownership and build
provenance. Launch failures retain their original cause. There is no shell
interpolation, persistent defaults update, state deletion or app termination.

Apple's [AppKit release notes, Ignoring Existing Restorable State](https://developer.apple.com/library/archive/releasenotes/AppKit/RN-AppKitOlderNotes/)
document `ApplePersistenceIgnoreState` for automated testing: existing restorable
state and untitled documents are ignored; new state and untitled autosaves are
redirected to temporary storage. Pass `-ApplePersistenceIgnoreState YES` only in
the new process's argument domain, together with `--open-document` and the fixture.
Do not use a persistent `defaults write` or delete saved-state directories.

Injected-runner tests cover exact arguments, paths containing spaces, production
identity rejection, malformed metadata, executable and fixture validation, launch
failure causes and CLI validation. They do not prove AppKit behavior on current
macOS. Controlled single-document startup, preservation of normal restoration,
unsaved recovery/history/save and clean closure require native acceptance before
#257 closes. No native app is launched by these contract tests. No production core
pin or quarantined engine path changes.

## Reviewed-base preparation

Prepared on merged targeted recovery PR258, retaining its replacement-load and
failed-shrink storage fixes. Only helper/tests/documentation change; packaging,
production core pin and normal application entry remain unchanged. Nine helper
contracts pass with injected runners; they never start Launch Services or native
apps. The archival AppKit source above was checked again, but current macOS
startup/restoration behavior still requires separate native acceptance. A full
local gate is required before publication.

## Public delivery gate

On the merged recovery base c6a9cdd5, the full make ci gate passed45 build-support
checks and941 XCTest cases (120.433s), formatting, coverage thresholds, Qt-free
source/link checks and isolated signed bundle/provider rebuild. All nine launch
contracts used injected runners or rejected invalid CLI metadata before launch.
No protected app was launched/contacted/controlled/rebuilt, and no defaults or
saved-state files were changed. The helper is a bounded command-construction
boundary, not build attestation or current-OS restoration acceptance. Keep #257
and broader M8 acceptance open. Production core pin and quarantines are unchanged.
