# Lossless document and undo foundation

The `Dust3DDocument` Swift library is an initial editor foundation, independent of
SwiftUI and Metal. It does not add editing controls to the viewer.

## Document contract

- Loading and encoding without edits returns the original archive byte-for-byte.
- A supported node position/radius edit produces a new immutable value. Unknown
  model elements/attributes/comments, header attributes, unrelated item metadata,
  arbitrary binary assets, payload gaps and trailing bytes are retained. Edited
  XML may normalize serialization; semantic retention is the contract after edits.
- Header offsets/sizes are recomputed when model length changes. The native engine
  reads an edited real Capsule fixture; an existing Sword round-trips exactly.
- The codec requires version 1.0, XML headers, UTF-8 XML and one canvas model. It
  rejects ambiguous names, overlapping/out-of-range items, duplicate node IDs,
  duplicate node containers, malformed XML and DTD/entity declarations. Limits:
  256 MiB archive, 1 MiB header, 16 MiB model, 10,000 items, 128 XML depth and
  100,000 element starts. The platform XML parser can impose tighter text limits.
- Node commands require finite coordinates/radius within absolute 1,000,000 and a
  nonnegative radius. Missing or invalid nodes fail without changing document or
  history. A no-op preserves exact bytes and creates no undo record.

This codec does not generate geometry. It can retain assets whose rendering is
unsupported by the current viewer. It is not yet the full graph/part/component
invariant model: topology commands, locks, schema migrations, modifier inspectors
and complete editing semantics remain M1/M2 work. Unknown data is preserved rather
than interpreted or silently converted into a partial editable model.

## Undo and persistence

`DocumentHistory` owns value snapshots. Each successful command is undoable; a
gesture transaction groups many updates into one step. Cancel restores its exact
starting archive. Nested transactions are rejected, undo/redo are unavailable
during a transaction, and failed/no-op commands preserve redo. New committed edits
clear redo.

History defaults to 100 entries and 64 MiB of retained archive bytes across undo
and redo. Oldest/furthest history is trimmed. Commands exceeding the configured
archive-byte budget fail before committing; callers may configure a larger budget.
The budget excludes the current document, savepoint, transaction snapshot and
object/XML overhead, so it is not a hard process-memory limit.

`DocumentFileService` reads off the main actor, bounds input, checks cancellation,
and writes with Foundation's atomic replacement. It preserves file-system errors
and balances security-scoped URL access. Save the captured snapshot, then record
that exact snapshot as the savepoint:

```swift
let written = history.document
try await files.save(written, to: url)
history.markSaved(written)
```

If edits arrive during the write, they remain dirty. A failed save must never
advance the savepoint. Document scenes, coordinated external edits, autosave,
crash recovery, file versions, bookmarks and UI `UndoManager` routing are later
integration work. Cancellation cannot interrupt a synchronous XML parse or an
atomic write already in progress.

## Verification

The suite includes independent archives with unknown fields/assets, real repository
documents, native-engine compatibility, malformed/bounded input, XML depth and
growth limits, no-op/failed commands, exact undo/redo, grouped/cancelled gestures,
history budgets, stale save completion, atomic replacement and file errors.

`make ci` enforces at least 95% measured line coverage for each Swift library and
100% for the pure undo domain. XML/file boundaries are included in the document
library measurement; defensive serializer paths and real security-scoped URL
release remain residual boundary coverage. C++ coverage belongs to core CI and is
not measured by this Swift gate. GPU/UI behavior is unchanged by this foundation.
