# ADR 0104: Manage stored animation intent independently of evaluation

Status: Local document foundation; native catalog/evaluation/UI acceptance pending (#145).

Read-only source audit of core document.cc create/name/type/parameter/delete/
duplicate methods, snapshot_xml.cc and the writer's flat animation tag selection
establishes the archive shape: canvas/animations/animation, with id/name/type and
all other attributes as string parameters. No Qt app or inherited writer was run.
Core #95 prohibits further native coarse-sampling probes; this stage neither
compiles nor calls animation, rig or sound generators and does not lift it.

Expose ordered DocumentAnimation rows, optional missing name/type, exact UTF-8
identities and an ordered parameter array. Swift canonical dictionary equality
must not merge byte-distinct source names. Retain unsupported types and raw timing
strings without promising runtime support or rewriting saved timing. Reject
ambiguous containers, missing/duplicate IDs and unknown tagged identities rather
than silently hiding input that upstream may interpret. Unidentified extensions,
comments, namespaces and nested opaque data stay retained.

Commands create, rename, change type, set/remove one parameter, duplicate and
delete. Fresh IDs come from the caller, keeping UUID generation out of document
logic. Names/IDs/types are bounded to 1024 UTF-8 bytes; IDs/types must be nonempty.
Parameter edits use unqualified ASCII identifier names up to128 bytes and values
up to4096 UTF-8 bytes; id/name/type/xmlns are reserved. Controls/newlines and invalid
XML text are rejected. Existing unsupported metadata remains readable/preservable;
this does not validate numeric timing, rig/clip compatibility or playback.

Archive XML keeps its existing16MiB bound. Reads/admission bound child elements
including opaque extensions to10000, with a smaller caller quota for metadata
listing. Append uses the same accounting. A two-element unit fixture with a
limit of two proves that an opaque extension consumes capacity; no bulk fixture,
allocator failure or resource-exhaustion probe runs. The proposed large fixture
was rejected by automatic approval review and was never created or executed.
The small unit-level alternative was explicitly recommended by that review.

Every edit returns a new archive value; no-ops preserve exact source bytes and
Redo. Unknown attributes/children and opaque assets survive, duplication clones
nested data in its original namespace context, deletion keeps assets and container
metadata, and a create/delete transaction can return to the exact clean archive.
Native reader compatibility of newly created intent, caller UUID/schema policy,
actor/store/list controls, native evaluation/playback/audio and full M6 acceptance
remain separate stages. Production pin and all quarantines stay unchanged.

Test-first compilation failed on the absent API. Pure XML/archive tests exercise
history/reopen, string escaping, namespaced duplication, exact asset bytes,
byte-distinct Unicode lookup, incomplete/unsupported intent, ambiguous metadata,
small quotas, invalid edits and no-op Redo. A reserved-xmlns regression initially
changed bytes/Redo instead of rejecting; parameter admission now excludes it.
The full local `make ci` passes 45 build-support tests and 978 XCTest cases
(119.983 seconds), including twelve animation-document tests, formatting,
coverage gates, Qt-free linkage and isolated bundle rebuild/signature checks.
Scoped coverage records 35/35 lines for public animation values/errors and
185/190 (97.37%) for the XML helper; it is not a 100% whole-domain/core claim.
Foundation copy/cast failure paths remain defensive boundary checks; no fault
injection is used to force them. This document stage has no UI screenshot.

A second history regression showed create/delete could leave an Undo record for
an archive that started with an empty animation container. Transaction comparison
now normalizes only metadata-free empty animation containers alongside the
existing empty graph containers. Attributes, namespace declarations, comments and
non-whitespace children remain significant. Tiny absent/empty/whitespace/comment/
namespace variants verify exact clean-archive restoration; no native writer or
animation evaluator is involved.


## Corrected animation-document delivery foundation

Replay saved `ec026ae8` on the validated editor export coordinator. Before delivery,
backport the in-place attribute update from later `ddc3f3af`. A new pure history
regression first failed six assertions: changing and restoring existing name,
type and duration in one transaction reordered attributes, changed archive bytes,
marked history dirty and discarded redo. Updating the existing XML attribute's
value retains its position. The focused regression then passes with exact source
bytes, unchanged clean history and retained redo; other stored fields stay opaque.
The later batch-edit stage must retain this already-applied fix rather than replay
an unfixed intermediate foundation.

Fresh full `make ci` passes 45 support tests and 979 XCTest cases (121.463 seconds),
formatting, configured coverage, Qt-link and isolated build-only bundle/signature
checks. Original foundation source hashes are preserved except this narrow helper
fix/new regression and inherited delivery notes. Existing quota tests use 2/3-row
units and small UTF-8 bounds; no previously denied bulk fixture or native animation
probe is run. This is lossless stored intent, not playback/sampling acceptance.
Production pin, quarantines and protected QA processes/bundles remain unchanged;
known ordinary pinned fixture SVG writes are not restored. Require accepted
parents, completed clean exact-head automated review and all CI green before merge.


## Parameter removal/restoration comparison

A second pure regression exposed the related remove-and-restore case: removing a
parameter and restoring the same value in one transaction reinserted its attribute
at a different position, changing bytes/dirty history and discarding redo. The
focused test first failed six assertions. The model comparison now orders direct
animation attributes by exact UTF-8 names in its separately parsed comparison
DOM only. Persisted XML is never sorted. When all intent matches, history restores
the original archive snapshot; row/child/comment/namespace order, raw values and
opaque assets are otherwise compared unchanged. Real removal and empty values
remain distinct, undoable changes in a separate regression. This extends existing
model-only net-zero comparison rather than changing normal serialization.

All 15 focused animation-document tests pass. Fresh full `make ci` passes 45
support tests and 981 XCTest cases (118.880 seconds), formatting, configured
coverage, Qt-link and isolated build-only bundles. Measured lines: animation value
35/35, XML adapter189/194, full document file1201/1222; no whole-core or full
Foundation-boundary coverage claim. No native animation, previously denied bulk
fixture, fault/crash/resource probe or protected QA control occurs. Production pin
and all quarantines remain unchanged; known ordinary pinned fixture SVG writes
are not restored. Both history corrections belong in this foundation before its
first publication; later batch editing must retain them. Full M6 acceptance is
still open.


Apple #264 merged at `004a198e` after completed clean exact-head automated review and all CI checks green. Full-tree equality across ancestry-only rebase and matching gated source hashes preserve the tested implementation. No native binary executes after rebase; only this delivery note changes afterward.
