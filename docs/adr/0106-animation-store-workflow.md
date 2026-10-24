# ADR 0106: Bind stored animation workflows to accepted editor source epochs

Status: Local actor/store foundation; native controls/evaluation/Qt acceptance pending (#145).

A row ID can recur after Open or exact Undo. AnimationEditTarget captures the
accepted document UUID, semantic revision and exact UTF-8 row identity. Actor
edits map a small typed AnimationEdit to the captured row, rather than trusting
current selection or caller-supplied command identities. Replacement and Edit/
Undo retire old targets; selection/interaction locks alone do not. Targeted
duplication validates before allocating/publishing a fresh UUID. Original catalog,
document and stale-target causes propagate without partial state or history.

EditorStore queries metadata explicitly. The owning visible pane will request a
refresh on appearance/source changes; generic graph snapshots do not trigger extra
catalog parses. One request UUID retires canceled/older responses, and source UUID/
revision checks prevent relabeling stale metadata. Rapid selection queries remain
latest-request-wins. A failed Open clears list state and never promotes a retained
preview as the attempted file. Reload/stop cancel and retire outstanding queries.

Optional catalog and query issues remain distinct from a valid empty list and from
primary graph errors. An invalid/missing selection does not dirty the document or
block graph Save/edits. Metadata mutation commands reuse the existing primary
operation/history publication, then refresh the list. They preserve static mesh/
material generations because changing stored animation intent is not evaluating
an animation. Undo uses the existing general workflow; old list revisions become
unavailable until an explicit refresh. Source/type/parameter errors retain their
original cause, and stale-target messages tell the user to select the source again.

Tests use small XML/archive values, a no-native preview substitute and cooperative
actor tasks. They cover targeted metadata edits/deletion/duplication, replacement
and Edit/Undo ABA, stable fresh identities, transient independence, current source
labels, latest selection, no document publication during selection, no geometry
regeneration during metadata edits, primary history, pending-query reload/stop,
failed Open and optional-error isolation. The full local `make ci` passes 45 build-support tests and 992 XCTest cases
(119.468 seconds), including eight new target/store tests, formatting, library/
domain coverage gates, Qt-free linkage and isolated bundle/signature checks.
Scoped target/edit values measure 23/23 executable lines. Whole EditorStore
measures 1160/1275 (90.98%), not a scoped workflow or 95% whole-shell claim. No native generator, bulk/resource-exhaustion
fixture, app control or production pin change occurs. Core #95 and all other
quarantines remain unchanged. Native list/inspector controls, screenshot/keyboard/
focus acceptance, Qt/runtime catalog interoperability, playback/audio and full M6
acceptance remain open.

A focused regression showed a missing-row query error could outlive its source
revision after a normal graph edit. Query failures now retain UUID/revision with
the original cause and are exposed only for the matching accepted source, just
like list results. The small no-native-preview test first observed the stale
error, then verifies retirement before any explicit list refresh. This adds no
native error/failure-injection probe.
