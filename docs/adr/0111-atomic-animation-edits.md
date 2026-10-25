# ADR 0111: Commit captured animation edits atomically

Status: Local implementation verified; review/publication pending.
Tracking: [#145](https://github.com/dalbrecht/dust3d-swiftui/issues/145).

Add EditorSession.editAnimations for an ordered group of stored-intent edits to
one captured animation row. Validate the document/revision target once, map every
command to that exact identity and apply through the existing history transaction.
Publish only after all commands and cancellation checks succeed. Single-edit calls
delegate to this path. The store uses its existing source-correlated non-rendering
workflow, including completion/error publication and metadata refresh.

This enables a future duration/frame-count form to commit both fields as one undo
step. It does not infer timing rules, normalize raw strings or depend on unpublished
core APIs. The production core revision and Package.resolved remain unchanged.
Ordered edits can include rename/type/parameter changes or deletion; an invalid
later command rejects the entire batch. Empty/net-zero batches retain history.

A missing-method regression failed before implementation. The first implemented
focused run exposed a real net-zero history defect: replacing an existing animation
attribute removed and re-appended it, changing its order even when its original
value was restored. Updating existing attribute values in place preserves order,
allowing the history comparison to restore original archive bytes and retain redo.
Absent/add/remove behavior and unknown unrelated metadata remain unchanged.

New session contracts cover two-field edits, exact single-step undo/redo, encoded
reopen, comments/unknown parameters/unrelated rows, invalid-later-command rollback,
empty/net-zero transactions and stale targets after edit/undo. A store contract
checks completion, both values, atomic failure, undo and unchanged preview revision.
All nine focused workflow tests pass after the defect fix.

Full make ci passes: 45 build-support tests and 1018 XCTest cases (122.949s), build,
formatting, coverage, Qt-free linkage and isolated bundle-rebuild regression. Line
coverage is 2755/2782 Swift mesh, 3834/3927 document, 1851/1857 editor model;
pure editor state535/535, undo97/97 and camera33/33. These are measured Swift
coverage results, not a claim of inherited C++ coverage or full feature parity.

No new visible UI is added, no protected QA application is controlled/replaced,
and no native interaction/screenshot acceptance is claimed. Existing ordinary
pinned-core fixtures retain their known SVG writer behavior; no global SVG restore
is attempted. Structured catalog-guided inspectors, reviewed core dependency
adoption, sampling/playback/audio and full M6 acceptance remain open. All existing
GLB/writer/fault/animation/rig-pose quarantines remain in force.


## Corrected-parent delivery validation

Replayed onto the validated creation stage, retaining publication-time selection
pruning, restored-parameter history comparison and observable native Undo/Redo
validation. The existing-attribute update fix was already accepted in the
foundation and is not duplicated or removed by this replay. All three focused
actor batch contracts pass (0.004 seconds), with small ordinary stored records
and no native animation evaluation. Fresh full `make ci` passes 45 support tests and 1,024 XCTest cases
(124.397 seconds), formatting, configured coverage, Qt-link and isolated bundle
checks for this combined source. Logs and source/test/manifest hashes retained
in the delivery checkpoint. No new UI, production dependency or quarantine change.
