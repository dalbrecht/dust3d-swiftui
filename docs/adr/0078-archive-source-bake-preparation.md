# ADR 0078: Archive-to-source-bake preparation

Status: Accepted for implementation; issue #165, M4 issue #143.

Build on ADR 0077 with an opt-in ArchiveSourceTextureBaking service. Read material
metadata, procedural image references and pixels from one immutable archive value,
then invoke the owned source baker with those exact bytes. Keep document editing,
history and serialization out of preparation. Return the SDK result unchanged,
including its material policy, exact catalogs and maximum sampling LOD.

Reuse ImportedMaterialLoader and ImportedImageDecoder for declared required
imported PNG/JPEG images. Reuse the legacy MeshPNGDecoder for procedural color
assets; its transparency compatibility policy intentionally differs from source
glTF decoding. Extract procedural admission/decoding into a shared internal helper
used by both archive baking services, avoiding a second subtly different PNG path.
No new dependency or second native adapter is introduced.

Imported inspection copies remain independently bounded by native/Swift quotas.
After inspection, check the combined encoded image budget before every pixel
decode. Count each required imported model image and distinct procedural image
reference. Decode all declared required imported textures; do not run a second
geometry generation just to filter the material inspection catalog. A future
usage-filtered inspection API may reduce unnecessary decoding of invisible models.

Use one remaining decoded-byte budget across both paths, capped by both archive
limits and source SDK input limits. Explicitly reject exhausted budgets and
preserve an individual decoder's quota cause when an image does not fit. These
are retained-data limits, not hard process RSS or generator CPU bounds. Temporary
indexes, codec/native workspace and allocator overhead remain excluded.

Preserve legacy asset names and original PNG failures. Wrap imported decoding
failures with the exact model identity and original typed cause. Never turn
cancellation into an image failure. Native/document failures propagate unchanged.
Run preparation on a background actor, delegate to the source baking actor and
check cancellation after each operation before publishing. Keep the baker
substitutable for cancellation/publication and original-error contracts.

Test real imported, procedural, textureless and mixed archives; exact combined
budgets, original codec/native failures, opaque asset preservation and cancellation.
Retain the existing procedural archive service regressions through the helper
refactor. Run the full local/review/hosted gates before publication/merge. Renderer
adoption, chart-isolated atlas mipmaps, broader material compatibility and export
acceptance remain subsequent work; this stage does not complete M4.
