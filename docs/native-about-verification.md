# Native About and diagnostics separation (#344)

Editor and Viewer now invoke AppKit's standard About panel through the shared
ApplicationAboutPanel boundary. The app's existing immutable build identity
supplies its QA-aware human name. AppKit uses the packaged icon, short version
and build defaults; raw source/core hashes do not replace the product version.
The exact root MIT notice and root CONTRIBUTORS/SUPPORTERS lists are copied into the rendering resource bundle and supplied as attributed credits, with the license copyright line and clearly separated credit headings. The lists remain available offline, retain upstream ordering and text, and do not initiate external navigation. Both app packagers
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
VoiceOver remain open. Project-link inventory,
dependency license/release auditing, native inspector contrast and full Apple
HIG/Qt parity remain separate. Production core pin and all quarantines remain.


## Offline upstream credits (#346)

A new regression against the license-only implementation failed one assertion:
the native credits omitted both checked-in lists. All six scoped About tests
then passed with the resource-backed lists. The combined attributed string is
compared exactly with the three root files, preserving their Unicode text and
ordering. Tests also verify explicit missing-resource messages and the original
localized read-error cause for each resource. They never open an About panel.

Both packaged apps must retain exact root bytes for ApplicationLicense.txt,
ApplicationContributors.txt and ApplicationSupporters.txt in their Rendering
resource bundles. This is upstream project attribution; it does not claim a
complete native dependency-license inventory or full Qt/HIG acceptance.
Physical standard-panel scrolling, dark/light layout, keyboard and VoiceOver
remain outstanding.
