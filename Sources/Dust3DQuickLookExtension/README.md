# Dust3DQuickLookExtension

Read-only interactive Quick Look previews with orbit, zoom, fit and wireframe controls.

Build and package using `./script/build_and_run.sh --editor --build-only`.
The editor owns the extension; installing the standalone viewer alone does not
install this provider. macOS discovers it from the editor application bundle.
No independent configuration or network access is required.

Shared bounded loading and rendering live in Dust3DRendering. Run `make ci`
for tests, formatting, linkage and packaged-bundle validation. Native Finder
and Quick Look acceptance additionally requires a graphical macOS session.

Image compatibility notices follow current baked output or GPU fallback. Legacy
surface limitations remain separate; metadata comes from the same read-only
archive snapshot. See [shared notice verification](../../docs/shared-material-notices-verification.md).
