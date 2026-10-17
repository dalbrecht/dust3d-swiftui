# Swift source hint verification

Tracking: #112. Design: [ADR 0056](adr/0056-copied-swift-source-hints.md).
Core pin: `17e04d55427578418460b270886846301eaa2a5d` (reviewed core #26/#28).

## Behavior and boundaries

`MeshGenerationSession.generateSourcedIndexed` returns independent indexed mesh,
source hints and statistics. Nil mesh/hints means explicit successful emptiness.
Ordinary session/stateless APIs retain their behavior. Source export, indexed
payload and retained cache budgets are separate; source zero defaults to 64 MiB,
indexed zero to 256 MiB, cache zero disables retention.

Hints preserve complete original weights and unknown/ambiguous identities. Future
kinds are retained as raw values; no arbitrary source or exact Boolean ownership
is invented. Corner i corresponds to index-array position i, not unique vertex i.
Original keys are bounded, strictly decoded UTF-8 and compared byte-exactly,
including case/combining-mark ordering. No UUID normalization or repair occurs.

The framework-free model rejects bad geometry/counts, negative/overflowing ranges,
invalid identities/sentinels, nonfinite/negative weights and inconsistent kinds.
The separate C copier checks payload/count minima before unsafe views and copies
all strings/arrays before native source destruction. The actor releases expanded
source ownership before allocating Swift indexed buffers, preserves typed primary
causes and independent cache warnings, and checks cooperative cancellation.

## Evidence

TDD red logs record missing value types, copy boundary and sourced actor API
before each implementation. Seventeen new tests cover:

- Pure node/weighted/unknown/ambiguous/future values; safe shared influence ranges;
  invalid geometry/identities/weights/indices/ranges/kinds, including Int extremes.
- Bounded C-string copies (nil/empty/unterminated/invalid UTF-8 and exact maximum),
  original UTF-8 byte ordering and byte-exact opaque identity equality.
- Native source-copy cancellation after generation, before metadata publication;
  pre-cancelled actor requests do not enter the engine. No hard C++ cancellation
  or deterministic interruption during native generation is claimed.
- Actual cached Capsule generation, edit/restore, copied lifetime after reset and
  actor destruction, separate source/index/cache limits and recovery, malformed
  archives and successful empty output.
- A real synthetic Cloth group retaining multiple node weights after a cache hit.
- A malformed archive whose legacy opaque identifier contains invalid UTF-8,
  accepted by the inherited C parser: Swift rejects its metadata with the original
  validation cause instead of repairing an identity, then recovers on valid input.

Full local `make ci` passed: **506 tests, two Metal-device skips, zero failures**
(74.752 s). Build, Swift formatting, coverage thresholds, Qt source/link checks for
both apps, and bundle/icon/archive rebuild checks passed. The skips are the existing
production Metal indexed/expanded comparison and renderer later-revision recovery
checks on a host without a Metal device; no new GPU acceptance is claimed.

Measured Swift coverage: SDK **535/542 lines (98.71%)**; new framework-free source
model **115/115 (100%)**; C copy boundary **81/82 (98.78%)**; complete generation
actor/statistics file **194/198 (97.98%)**. The copy gap is the defensive nil-corner
pointer rejection; actor gaps are native owner/create/reset/statistics failures
that validated native calls did not produce. No artificial invalid handles were
created to exercise those paths. Existing document/model/state/undo/camera gates
also passed. These are Swift scopes, not inherited C++ coverage claims.
No production fault switches, new dependencies or unchecked Sendable declarations
were added. No UI changed; no new native GPU, VoiceOver or Qt GUI parity claim.
The thin C boundary retains defensive validation paths; inherited geometry coverage
and full Qt modifier acceptance remain separate adoption work. Editor metadata
and source-based picking integration follow after this reviewed SDK stage.
