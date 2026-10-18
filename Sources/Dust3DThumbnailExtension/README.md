# Dust3DThumbnailExtension

Rendered Finder thumbnails of the procedural object, including available baked materials.

Build and package using `./script/build_and_run.sh --editor --build-only`.
The editor owns the extension; installing the standalone viewer alone does not
install this provider. macOS discovers it from the editor application bundle.
No independent configuration or network access is required.

Shared bounded loading and rendering live in Dust3DRendering. Run `make ci`
for tests, formatting, linkage and packaged-bundle validation. Native Finder
and Quick Look acceptance additionally requires a graphical macOS session.
