# ADR 0073: Copy imported surface source facts into Swift

Status: implemented under #155; review pending.

Core #49 preserves imported corner UVs/model ownership internally; #51 adds an
owned C boundary aligned after float geometry filtering. Pin its merged revision
0a83c3e3a59da4bafb5e3e83023fffd7df5cca90 through SwiftPM and committed resolution.
No native adapter is copied back into the Apple repository.

Add immutable Sendable Swift geometry/source values, separate from packed atlas
metadata and decoded material images. Preserve raw finite source UVs outside 0–1,
straight source RGBA with explicit linear/sRGB encoding, optional bounded catalog
indices and byte-exact component identities. Generated catalog membership does
not assert unique Boolean provenance. Material factors and source texture samples
remain independent inputs for a subsequent sampling/rendering stage.

The synchronous loader validates options, native retained counts/payload, source
flags, finite coordinates/colors and references before publication. A background
actor checks cancellation before and after the serialized native operation; copy
loops check between records. Native buffers are always destroyed with their owner
on success or failure, after copies complete. Original native failures retain
status and diagnostic; Swift boundary failures use typed actionable errors.

Native and copied Swift data have independent 64 MiB default / 256 MiB maximum
budgets. Swift charges retained records, array capacities, identity byte lengths
and warnings. Temporary catalogs/indexes, decoder/generator workspace and allocator
overhead are excluded; this is not an RSS cap. This API introduces no dependency.

Acceptance uses real imported/procedural fixtures, mirror catalogs, ownership and
quota edges, malformed source records, original errors, background cancellation
and exact GLB preservation through edit/undo/save/reopen. Full make ci and review
remain required. Imported sampling, atlas/baking, PBR/alpha presentation, rendered
file-preview parity and textured export still require separate M4 acceptance.

Automated review follow-up: resolved model IDs use an explicit byte-exact Hashable
value, with bounded construction, so normal equality/dictionary lookup preserves
original engine keys. A narrow internal geometry-copy dependency allows a real
copy followed by deterministic cancellation in tests; the synchronous boundary
checks cancellation again after that copy and before publishing. No test hook or
mutable global is added to the public API.

The component catalog also exposes this shared ImportedSurfaceIdentity key type,
not a raw String. Component entries synthesize Hashable from the typed key and
catalog kind. Both model/material and component/binding correlation therefore
require explicit byte-exact keys; rawValue is reserved for display/serialization.
