# ADR 0072: Owned imported materials and bounded image decoding

Status: Accepted for implementation, Apple issue #153

## Context

The reviewed portable core now resolves embedded geometry and exposes an owned C
material/image inspection handle. Apple apps need original material facts and
independent encoded/pixel storage without retaining native pointers or conflating
model identities with ordinary image asset identifiers.

## Decision

Pin core 4db1bb770b4c342446805f77ccfa4dc0aabc90c4, including geometry PR #43 and
material owner PR #47. Keep all C++ adaptation in that repository. Copy factors,
alpha/sampler presence, exact UTF-8 bindings and PNG/JPEG bytes before destruction.
Validate counts, identities, values, flags, pointer/count pairs and binding indices
before use. Charge record storage, copied identities and images to an independent
Swift logical output quota; indexes and allocator/native workspace are excluded.
This is not a process memory cap. Native errors preserve their original cause.

Use an actor service for serialized background inspection and pixel decoding.
Return immutable Sendable values. Check cancellation before/after synchronous work
and per decoded row, without claiming preemptive codec/native cancellation.

Preserve the established PNG source-sample policy. Share only sample-layout logic
with JPEG, translating typed sample failures back into format-specific errors.
Before ImageIO, inspect one complete JPEG envelope with bounded marker lengths,
eight-bit sequential/progressive frame dimensions and scan boundaries. Reject
alternate frames, dimension redefinition, unsupported precision and trailing data.
Structural success is not codec success: ImageIO must still decode the pixels.
Enforce encoded size, 8192-per-side dimensions and final RGBA8 storage before pixel
allocation. Codec workspace is outside the quota. RGB/grayscale layouts work;
CMYK and unsupported layouts fail explicitly. Keep orientation, source samples,
material factors and sampler policy separate. Do not premultiply base-color alpha.

## Consequences and verification

Real C-owner and independent archive fixtures verify copied metadata, aliases,
shared/uninstanced bindings and byte-exact assets after edit, undo, redo and reopen.
Known PNG samples test straight alpha; baseline/progressive/grayscale JPEGs test
owned RGBA shape/opacity. CMYK and malformed-codec fixtures test explicit failures.
Budget and malformed C view tests cover the ownership boundary. Full native CI,
coverage, Qt-free checks and bundle rebuilding are required before review.

Imported geometry remains a preview with an unapplied-material warning. This stage
does not complete imported corner UV propagation, Boolean/cache material ownership,
baking, PBR/alpha rendering, rendered file previews, textured exports or Qt parity.
Those remain required by editor-port-plan.md and core issue #41. No second native
adapter, image library dependency or local rendered baseline is introduced.
