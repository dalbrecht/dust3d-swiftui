# Native project Help commands (#348)

Both native apps now expose the same Help destinations through
ApplicationHelpLink: the native GitHub project, its issue-report form, and the
clearly labeled upstream Dust3D website. The Qt reference provides homepage and
issue-report actions in application/sources/document_window.cc; core b475c730
application/application.pro specifies https://dust3d.org/ as its homepage. Native
reports intentionally target dalbrecht/dust3d-swiftui rather than the upstream
tracker so downstream issues reach the maintained native application.

SwiftUI still constructs and routes ordinary menu buttons. Navigation starts
only in the explicit action. The imperative bridge is one NSWorkspace.open call
on the main actor; a declined Bool result is not described as successful loading
or a confirmed browser/network response. A typed LocalizedError retains the
destination and invalid/declined reason through the standard NSApplication error
presentation. There is no browser controller, network client or application state
mirror. No document selection or dirty/history state participates in these links.

Four regression-first contracts failed compilation because the new API did not
exist, then passed with fake opener/reporter closures. They cover exactly one
native issue-form request, destination-specific declined-open feedback, invalid
addresses rejected before the platform boundary, and distinct project/upstream
routes. No browser or error panel opened during these tests. An initial command
from the QA42 checkout matched zero tests and is explicitly excluded from the
regression evidence.

The full committed production-pin make ci gate and isolated bundle/archive
checks are required before publishing. Source wiring and injected tests do not
establish physical Help menu, keyboard, default-browser, error panel or VoiceOver
acceptance. Existing AX observer calibration cannot establish that acceptance.
Dependency pin and all core/animation/import quarantines remain unchanged.
