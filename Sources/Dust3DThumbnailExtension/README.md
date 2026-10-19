# Dust3DThumbnailExtension

Rendered Finder thumbnails of the procedural object, including available baked materials.

Build and package using `./script/build_and_run.sh --editor --build-only`.
The editor owns the extension; installing the standalone viewer alone does not
install this provider. macOS discovers it from the editor application bundle.
No independent configuration or network access is required.

Shared bounded loading and rendering live in Dust3DRendering. Run `make ci`
for tests, formatting, linkage and packaged-bundle validation. Native Finder
and Quick Look acceptance additionally requires a graphical macOS session.

Supported part-linked embedded GLB models use the shared imported renderer with
authored UVs, source images, sampler/mip policy, factors, alpha and sidedness.
Unsupported component-link forms still reject rather than disappear. Original
archives are read-only and need not be re-saved. Imported atlas/baking, additional
maps/features and exports remain open; see
[ADR 0076](../../docs/adr/0076-imported-material-file-previews.md).
