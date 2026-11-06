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

The two metadata tests first failed compilation because ApplicationAboutPanel
was absent, then passed. They verify QA naming, exact resource/root-license
identity, copyright and the absence of app version/build overrides, plus explicit
missing-resource feedback. They construct options without opening a panel,
activating an app or controlling an existing window. The native panel call is a
thin manual-verification boundary, not a fake-window acceptance claim.

Full local build/test/archive and both packaged attribution checks are required
before publishing this stage. Physical panel layout, keyboard, appearance and
VoiceOver remain open. Full contributor/supporter/project-link inventory,
dependency license/release auditing, native inspector contrast and full Apple
HIG/Qt parity remain separate. Production core pin and all quarantines remain.
