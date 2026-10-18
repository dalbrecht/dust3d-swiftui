# ADR 0070: Representation-aware material notices across native surfaces

Status: locally implemented and verified for Apple #142; PR review/remote CI pending.

## Decision

Move the pure `MaterialPreviewWarning` policy from EditorModel into Dust3DKit,
which already owns copied mesh warnings and is shared by all native surfaces.
The viewer and system preview must not depend on editor state to describe a mesh.
No package dependency or core revision changes. Existing engine warning strings
remain unchanged in geometry; presentation recognizes only the exact pinned
image-only and combined image/surface notices. Unknown warnings stay verbatim.

When current baked output is available, the image-only warning disappears. The
combined warning becomes a surface-only warning when legacy metadata is present,
disappears when that metadata is absent, and says surface details could not be
verified when interpretation is unavailable. It never claims a displayed image
is untextured. Ordinary geometry, failed baking and GPU/material fallback retain
the original geometry warning. Image baking does not establish legacy surface
parity; nonempty wrapPattern/wrapWrinkles retain their separate limitation.

## Source and lifecycle boundaries

`MaterialSourceCapabilities` is an immutable known/unknown/unavailable value.
Unavailable retains the original typed error; it is never fabricated as false.
`MeshFileService` derives it from the exact archive snapshot off-main, alongside
geometry and the bytes used for subsequent baking. The read is best-effort:
stricter Swift interpretation cannot break a valid primary native mesh load.
Cancellation checks surround synchronous parsing. The document reader's existing
bounds apply; parser workspace is not a total RSS guarantee.

Viewer source metadata follows the same request/revision acceptance as its mesh.
Replacement cannot pair old capabilities with new geometry; stop clears them.
The original source interpretation cause remains visible independently of
optional material/GPU failures. Existing bake request IDs continue to reject
obsolete output.

Quick Look already parses and validates document components before generating
geometry. It derives capabilities from that same parsed value, without a second
read or parse. The immutable `FilePreviewDocument` carries them to the host;
`compatibilityWarning(materialRenderingFailed:)` is independently testable.
The host owns available size: remove the SwiftUI root's fixed 320-point minimum
and adapt the footer with ViewThatFits so narrow native preview columns wrap
notices instead of clipping them. The controller retains its 640×480 preferred
floating preview size. Embedded/unsupported primary links remain rejected, not
downgraded into a partial object. The host switches back to its ordinary notice after GPU failure.

## Verification

Regression tests cover image/legacy/unknown/unavailable combinations, retained
original errors, real read-only file snapshots, a core-readable document whose
optional Swift component interpretation fails, late metadata after viewer stop,
GPU fallback and real image-bearing Quick Look baking. Inputs are unchanged.
Native viewer/system-hosted Quick Look and full-gate results are recorded in
[verification](../shared-material-notices-verification.md). Broader M4–M8 parity
and exhaustive VoiceOver/codec behavior remain separate acceptance requirements.
