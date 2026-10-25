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


## Captured animation coordinator delivery validation

Replay saved `81cd4f93` on the validated actor/list delivery and corrected XML
foundation. Actor/store implementation and new tests match the saved tested stage;
retain both existing-field and remove/restore exact-history regressions. Captured
row UUID/revision checks reject reopened or edited/undone source epochs while
leaving transient graph selection and locks independent. Query failures retain
original optional causes without blocking primary document editing.

Fresh full `make ci` passes 45 support tests and 995 XCTest cases (122.190 seconds),
formatting, configured coverage, Qt-link and isolated build-only bundle/signature
checks. Captured-target value/command coverage is 23/23 lines and 14/14 regions;
Swift supplies no branch outcomes. Tests use small stored-intent documents and
no-native preview, with query/load/stop/stale-target checks. This is not a
whole-EditorStore coverage, native UI, animation sampling or full M6 claim. No
production pin/quarantine or protected QA control changes occur; known ordinary
pinned fixture SVG writes are not restored. Only delivery notes change after the
gate with tested hashes unchanged. Require accepted parents, completed clean
exact-head automated review and every CI check green before merge.


## Integrate the actor review correction

The unpublished store stage now includes #266's selection-publication correction
and its no-intermediate-read history regression. Fresh full `make ci` passes 45
support tests and 996 XCTest cases (120.072 seconds), formatting, configured
coverage, Qt-link and isolated build-only bundle checks. Compared with the prior
store delivery, only the actor correction, its regression and inherited release/ADR
notes change. Logs and runtime/test/manifest hashes are retained in the corrected
store checkpoint. No native animation evaluation, production pin change or
protected QA app control. Parent acceptance, exact-head clean review and all green
CI remain required before public delivery/merge.


Apple #266 merged at `2e7b2b06` after completed clean exact-head Codex review
and all three CI checks passed. Full-tree equality and matching gated runtime,
test and manifest hashes prove the ancestry-only store rebase preserves the
validated source. No native executable runs after rebase; only this note changes.
