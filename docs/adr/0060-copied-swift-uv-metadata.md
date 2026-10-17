# ADR 0060: Copied Swift UV metadata

Status: Accepted for implementation; Apple issue #121.

## Context

Reviewed core PRs #31/#32/#34 provide numeric packer safety, portable atlas
construction and an owned C metadata boundary. The Apple app remains pinned to
an older reviewed revision. Swift needs copied Sendable values before baking or
rendering can consume UVs, and inherited source association does not establish
unique Boolean material ownership.

## Decision

Pin exactly to core 9577f8a44966841cf1c946adc726b12ef17e24c5 and commit SwiftPM's
resolved state. Add an opt-in MeshLoader.loadWithUvMetadata SDK API; keep ordinary
and cached editor preview behavior intact. This stage does not activate textured
rendering or change native UI.

Represent copied corners, charts, gradients and component associations as immutable
Sendable values. Validate counts and aggregate native C array sizes before unsafe
views; validate finite normalized coordinates/colors, mapping markers, source
indices, chart bounds and gradient references in a pure model. Chart edge sums
allow only a 1e-6 packing-intermediate rounding tolerance; individual UV/channel
ranges remain strict. Keep unknown mappings, aliases and future native component
kinds explicit, without inventing source identities.

Reuse bounded strict UTF-8 source decoding, preserving original component bytes.
Compare image and component identity bytes exactly: Swift's Unicode-equivalent
String equality is broader than engine identity. Image chart IDs use canonical
engine notation, while original component spellings remain unchanged.

Image descriptors supply dimensions and identities only. Validate count, UUID
shape (preserving opaque characters/case), duplicate engine aliases and dimensions
before crossing C. Copy borrowed metadata before releasing its owner. Create an
independent indexed owner, release UV/expanded ownership, then copy indexed data.
Retain original diagnostics and check cooperative cancellation before generation,
through copying and before returning. Native generation itself is not interruptible.

## Alternatives and consequences

Borrowed C buffers cannot safely cross actors or outlive owners. Adding UVs to
existing indexed vertices would misrepresent sharing: current indexed keys omit
UV/material seams. Keep metadata aligned with triangle-index positions until a
textured indexed representation is implemented. Automatically enabling the
stateless atlas path in cached preview would add generation work before any
renderer consumes it, so adoption is explicitly opt-in.

The native metadata quota is 64 MiB by default, maximum 256 MiB, and excludes
geometry/workspace/allocator capacity and Swift copies. Indexed geometry has its
own existing quota. No new dependency is introduced. Native M3 acceptance,
complete UV mapping, CPU baking/PBR/transparency, decoded image handling, GLB
import/export, full Qt parity and distribution remain separate milestones.
