# Shared Metal rendering

Internal SwiftPM target used by the separate viewer and editor executables.
`MeshViewport` bridges SwiftUI to a main-actor MTKView; it copies validated mesh
buffers into Metal and loads Shaders.metal from this target’s resource bundle.

Supply a mesh, wireframe flag, camera-reset counter and an error callback.
Increment `meshRevision` when replacing geometry to retain the orbit camera;
change `cameraReset` to fit again. The viewer recreates its viewport on file open.

Build with `make ci`; package with `script/build_and_run.sh --build-only` or
`--editor --build-only`. GPU interaction remains a manual verification boundary.

Camera fitting uses the narrower viewport axis around the normalized mesh bounds.
Resizing preserves orbit and relative zoom; Fit resets both. Both depth planes follow
the fitted distance to preserve depth precision for very narrow viewports. `Dust3DRenderingTests` covers the
pure camera at 100% line coverage, including a real disjoint-sphere core mesh.
This does not measure Metal draw or native input coverage.

Both apps supply `IndexedMesh`: the renderer uploads unique vertices plus a UInt32
index buffer and uses indexed triangle draws. The existing `MeshViewport(mesh: Mesh, ...)`
initializer keeps expanded callers compatible. Pure `RenderGeometry` validates
triangle buffers and normalizes bounds, then checks actual GPU-layout byte lengths
against the device buffer limit before GPU allocation. `MeshRenderer.encode`
is shared by drawable presentation and offscreen GPU verification.

`IndexedMetalRenderingTests` compares solid/wireframe indexed output with expanded
output on the same device. It explicitly skips when no Metal device exists.
Set `DUST3D_METAL_QA_OUTPUT_DIR` to write optional local evidence PNGs; these are not
committed visual baselines. Interactive window/input verification remains separate.
