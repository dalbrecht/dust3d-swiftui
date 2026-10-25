# ADR 0115: Reviewed core dependency upgrade

Issue: #272. Status: local validation passed; public review pending.

## Decision

Update the exact SwiftPM core revision from
`41af7d4c1b67dd037e02858e3ef0fdb96a84aebb` to
`48b0ce2d6d61cf58731bb0c3e14ef5965a686d68` (merged core #212).
The user authorized this separate delivery. SwiftPM generated the resolved file.
Apple still consumes only Dust3DEngine; worker/export executables are not activated.

The maintained core removes the automatic stitching SVG call and writer.
The source-only GLB catalog guard passes against the exact resolved checkout.
Preserve core #67/#69, #83, #84, #95 and Apple #199 quarantines. This upgrade does
not authorize quarantined evaluation, new malformed-input/fault/cancellation or
pressure probes, worker activation or protected-app control.

## Audit and evidence

The dependency adds export and animation metadata sources and a separate worker
runtime product. Shared generation output selection and validation change; this
is broader than the SVG removal. Numeric conversion failures now retain their
original causes in typed document errors. Existing document/import/session
fixtures therefore remain important compatibility checks.

Fresh source resolved and compiled in the single shared root
`/private/tmp/dust3d-validator-safe-build`. Full `make ci` passed: strict formatting,
45 build-support tests, application build, 1,004 XCTest cases with zero failures,
coverage thresholds, Qt-free linkage and viewer/editor bundle-rebuild checks.
No new native probes or app launch were added. Existing historical boundary tests
are included; this is not a pure/fake-only test result.

Measured line coverage: mesh library 2755/2782; document 3838/3934; editor model
1836/1842; pure editor state 535/535; undo domain 97/97; orbit camera 33/33.
These are scoped Swift metrics, not inherited C++ coverage or full parity.
The existing SwiftPM native-builder deprecation warning remains.

Completed exact-head automated review and all CI checks remain required before
merge. GPU, release signing, containment and broad differential acceptance remain
open. Preview scheduling #271 stays on its separate preserved branch for delivery
after this dependency stage.
