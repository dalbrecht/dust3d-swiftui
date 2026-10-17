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
