# Editor foundation verification

Verified October 14, 2026 with Swift 6.4 on Apple Silicon, targeting macOS 14+.

- `make ci` passes formatting, full pinned engine/viewer/library builds, shell
  syntax, 39 XCTest cases, coverage thresholds and Qt source/link checks.
- The migration alone passes the original 18 tests. Its app bundle was staged and
  ad-hoc signature verification passed using `script/build_and_run.sh --build-only`.
- New tests cover archive ambiguity/bounds/size/depth/growth limits, unknown
  XML/header fields, comments, binary assets, payload gaps, byte-perfect no-op
  saves, native-reader compatibility, atomic writes/errors/cancellation, exact
  undo/redo, bounded histories, cancelled/net-zero gestures and stale savepoints.
- Document library line coverage: **300/304, 98.68%**. The pure undo domain is
  **84/84, 100%**. The mesh library remains **66/67, 98.51%**. CI now enforces
  95% for both libraries and 100% for the pure undo domain, with missing files
  treated as a failure. These figures do not measure C++ or Metal/UI coverage.
- Residual lines are defensive XML serialization and real security-scope boundary
  paths. No artificial native hook or dead branch was introduced to inflate coverage.
- Builds ran in the fully local `/private/tmp/dust3d-editor-foundations` checkout
  because this workspace's File Provider interrupted Git/native file mappings.
  The workspace fast-forward was recovered without discarding user changes.

The viewer rendering code is unchanged; its earlier manual camera/UI checks remain
the visual baseline. This increment adds no editor UI. Portable core document APIs,
full graph commands, scene/UndoManager integration, file coordination and autosave/
recovery remain later work. See [foundation scope](editor-foundations.md).
