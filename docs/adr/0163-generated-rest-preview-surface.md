# ADR 0163: Independent generated-rest preview surface

Status: Experimental local-core integration, Apple #367 / core #330 / M5 #144.

RigTemplateBoneBrowser captures its already-bound snapshot into the immutable
GeneratedRigPreviewRequest. Only that source request/retry drives generation.
The generated preview is a sibling of template browsing and assignment controls;
it never writes document data or calls the old pose controller.

GeneratedRigDisplayState prepares skeleton and body on a detached worker from
copied rig data. Its key is generated-rig UUID, exact selected-name UTF8, and
resolved platform palette; camera state is excluded. Selection and appearance
therefore never regenerate the rig. Fresh publication epochs reject stale
success, failure and GPU callbacks. Entry cancellation guards prevent an obsolete
cancelled task from replacing newer work. Both source and display errors retain
the original diagnostic.

The display retains mesh and its originating rig UUID while refreshing. Only
matching-generation geometry mounts; unmatched colors are hidden and cannot
receive pointer input. Keeping the same viewport identity preserves the camera
through display refresh and cancellation gaps. Accepted mesh revisions increase
without reusing old values. Source replacement intentionally creates a new view
and clears prior camera commands. Camera/Fit actions validate their captured
source request and published rig epoch, including commands queued from old menus.

The picker uses optional source indices scoped to the rig UUID, never String
identity. It includes every generated joint, including unplaced zero-axis and
appended eyelid joints. Incoming template selection resolves by exact UTF8;
canonical-equivalent names remain distinct. Explicit no-highlight is retained
only within its rig epoch. Selected coordinates, a weight-color legend, warnings,
joint count and selected-name text accompany the GPU surface. Native camera-menu
and Fit actions provide keyboard alternatives; the Metal surface is AX-hidden.
This is not physical HIG/VoiceOver or equivalent numerical-weight accessibility
acceptance.

TDD: missing display/selection APIs RED5166; retained-mesh provenance RED64550;
camera interaction guard RED75585. Focused final pure run21842 passes32 tests.
Measured pure display93/93 lines, selection9/9, generation79/79 and composition
58/58, all120/120 regions and38/38 functions. Earlier experimental run20647
compiled the complete surface and passed31 scoped tests before the final camera
query/file organization changes. Final exact-commit experimental and production
gates are still required.

An initial production gate passed71 support tests and all1735 XCTest tests
(1733 pass, two expected accessibility skips), including existing ordinary Metal
rendering tests which compiled/executed the changed shader. It then failed coverage
accounting because a declaration-only GeneratedRigSkeleton file had no executable
record. Group its values/native factory with executable preview composition;
keep the all-file coverage checker unchanged. No artificial coverage branches or
missing-file exemptions are introduced. Offline Metal compilation remains
unavailable without the host Metal Toolchain; generated alpha appearance and
physical UI remain unaccepted.

Production core48b0, QA52 default, protected QA process and quarantines are
unchanged. Coree63 remains local only. No new pose/animation/GLB/writer, broad core
catalog, GUI automation or screenshot probes are added by this feature.
