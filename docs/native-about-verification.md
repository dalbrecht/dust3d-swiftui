# Native About and diagnostics separation (#344)

Editor and Viewer now invoke AppKit's standard About panel through the shared
ApplicationAboutPanel boundary. The app's existing immutable build identity
supplies its QA-aware human name. AppKit uses the packaged icon, short version
and build defaults; raw source/core hashes do not replace the product version.
The exact root MIT notice is copied into the rendering resource bundle and
supplied as attributed credits, with its copyright line. Both app packagers
already copy that shared bundle. Missing/unreadable attribution appears as an
explicit message, retaining a read failure's localized cause.

Help > Build Diagnostics opens the existing identity view under a clearly named
window. Its window ID and immutable startup capture remain intact. This is a
small app-level AppKit call; SwiftUI owns command routing, and AppKit owns panel
creation/lifecycle. There is no global custom panel/controller or mirrored state.

Primary contract: [NSApplication standard About panel options](https://developer.apple.com/documentation/appkit/nsapplication/orderfrontstandardaboutpanel(options:)).

## Evidence and scope

The initial two metadata tests first failed compilation because ApplicationAboutPanel
was absent, then passed. They verify QA naming, exact resource/root-license
identity, copyright and the absence of app version/build overrides, plus explicit
missing-resource feedback. Bundle review then exposed that the existing name
resolver recognized only the older combine-QA ID. A third regression using the
actual graph-QA bundle ID failed two assertions; both recognized QA IDs now retain
"Dust3D Editor QA" while normal/unknown IDs preserve their existing fallback.
These tests construct options without opening a panel,
activating an app or controlling an existing window. The native panel call is a
thin manual-verification boundary, not a fake-window acceptance claim.

Full local build/test/archive and both packaged attribution checks are required
before publishing this stage. Physical panel layout, keyboard, appearance and
VoiceOver remain open. Full contributor/supporter/project-link inventory,
dependency license/release auditing, native inspector contrast and full Apple
HIG/Qt parity remain separate. Production core pin and all quarantines remain.

## Installed resource lookup regression

Review of PR345 found that Bundle.module searches the application root and an
absolute build-time location, while the packager installs the rendering bundle
under Contents/Resources. The resource files and signatures could be correct
while the runtime lookup still failed on another machine. Resolve the embedded
bundle first; for a packaged .app with missing resources, return visible missing
attribution without touching the potentially terminating development accessor.
Only command-line/development hosts may use the lazy fallback.

Three new metadata tests cover embedded lookup, absent packaged resources and
development fallback. Initial compilation reproduced the missing injection API;
all six About tests then passed. An extracted archive check compiled the actual
About source into an owned metadata-only executable with an instrumented
Bundle.module that has no build-resource path. The old source consulted that
accessor once and failed embedded-license validation for both apps; the fixed
source read both exact licenses with zero consultations. No original build
resources were moved, GUI executable launched, panel shown or archive modified.
This check now runs in the existing isolated bundle/archive gate. Physical About
appearance, keyboard and VoiceOver remain separate.
