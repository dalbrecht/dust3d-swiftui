# ADR 0056: Copied Swift mesh source hints

Status: Accepted for implementation; automated review and all CI remain required.

## Context

Core PRs #26 and #28 expose bounded per-corner source hints, including cached
loads. The Apple apps need immutable values without borrowing native owners or
losing preview cache reuse. Position associations are quantized hints and can be
unknown, weighted or ambiguous; exact Boolean/component ownership is unavailable.

## Decision

Pin the reviewed core merge `17e04d55427578418460b270886846301eaa2a5d` and its
SwiftPM-generated resolution. Add `generateSourcedIndexed` to the existing
background `MeshGenerationSession` actor. Ordinary `generateIndexed`, stateless
loaders and viewer behavior remain compatible and do not allocate source exports.
Return a separate Sendable sourced result with optional indexed mesh/hints and
copied cache statistics. Both mesh/hints are nil only for explicit successful
NO_GEOMETRY. Keep cache-only diagnostics separate from primary errors.

Define immutable Sendable identity, influence, corner and hint values. Preserve
all finite nonnegative weights without renormalizing or picking one arbitrary
node. Unknown/ambiguous identity sentinels become nil indices; future raw kind
values remain explicit. Corner ordinal i matches triangle index position i, not
unique render vertex i. The identity table retains original opaque key spelling.
Use UTF-8 byte-exact identity equality: Swift canonical String equivalence is
broader than inherited engine identity comparison. Do not normalize to UUIDs.

Keep pure DTO validation in a framework-free file. Validate positive complete
triangles, corner count, weights, identity indices, corner-kind consistency and
nonnegative bounded ranges using subtraction before addition. Allow safe shared
ranges; the C contract does not require disjoint influence storage. Future kinds
remain bounded without being interpreted as a known association.

At the C boundary, validate count/payload minima before forming unsafe views.
Bound identity reads to the reviewed native parser's 38-byte maximum plus a
terminator, require nonempty valid UTF-8 and reject invalid encoding. Never use
repairing C-string decoding to silently change an opaque original key. Preserve
validation causes in typed `MeshLoadingError` diagnostics.

The actor validates source budgets before `size_t` conversion (zero defaults to
64 MiB, maximum 256 MiB), separately from indexed and retained-cache budgets.
Source owners are held by defer during metadata copying/index conversion, then
released before Swift indexed copies allocate. Independently indexed handles
transfer directly into the existing ownership-consuming copy helper. No pointer
escapes a synchronous lock region; no new unchecked Sendable declaration.
Cancellation checks occur before work, after native work, during identity copying,
between metadata phases and before publication. C++ work is not interrupted.

## Consequences

Swift clients can consume cached source metadata safely. Invalid source metadata
fails this opted-in SDK operation; it does not mutate archive/history or change
ordinary loading. Native generation may have completed and retained a valid cache
before a Swift-copy rejection, so later valid requests still use normal invalidation.

Editor preview metadata/picking adoption is a subsequent reviewed stage. No UI
screens or GPU rendering changed here. M3 and the larger parity/Qt acceptance
matrix remain incomplete. No dependency beyond the reviewed core pin or license
change is introduced.
