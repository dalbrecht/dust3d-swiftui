# Native viewer verification

Verified October 14, 2026, using Apple Swift 6.4 and Apple Clang 21 on Apple Silicon, targeting macOS 14+.

The implementation is in the main workspace. Because this checkout is backed by a File Provider and native compiler reads waited on placeholder headers, final validation used a fully local checkout at `/private/tmp/dust3d-native-source`, at the identical base commit `3fbcaa7a3e8792d1c2ca31ca2ade442dcd21b222`, with the new package, adapter, Swift sources, scripts, and tests copied from the workspace. No engine or vendored C++ implementation was changed. Compiler caches are outside the synced checkout. For a cloud-backed source folder that still delays reads, use a fully local clone for compilation.

## Automated checks

- `make ci`: passed native source formatting, shell syntax, the full engine/viewer build, 18 XCTest cases, and Qt source/linkage checks.
- `Dust3DEngine`: static library built, including geometry and required vendored dependencies.
- Swift compiler warnings are treated as errors. The original `.clang-format` and C++17 setting are preserved.
- Independent fixtures: `Capsule.ds3` is generated with the repository's Python archive writer; `Sword.ds3` is generated from the existing sword JSON example. Tests verify real geometry, color, finite unit normals, ownership after another load, legacy edge orientation, malformed archives, duplicate identifiers, oversized input, unsupported imports, file-system errors, and cancellation.
- New Swift document library line coverage: **66/67 lines, 98.51%**. `Mesh.swift`: 100%; `MeshFileService.swift`: 100%; `MeshLoader.swift`: 97.78%. The uncovered loader line guards an invalid empty handle returned by native code; the adapter never returns that state. No dead code or artificial test hook was added to increase coverage.
- The C++ engine and Metal/UI are not represented by this Swift coverage measurement. The XCTest cases exercise the C bridge and real engine behavior; they do not establish 100% inherited engine coverage.
- The build reports inherited C++ warnings: signed one-bit UV packing flags and deprecated `sprintf` calls in the original `.ds3` writer. New adapter formatting is clean; these adopted-code issues are recorded rather than hidden by global warning suppression.
- The local app bundle is ad-hoc signed; `codesign --verify --deep --strict` validates the staged bundle. Native viewer linkage contains no Qt frameworks.
- Final packaging stages the app outside File Provider folders and delivers `dist/Dust3DViewer.zip`. The ZIP was extracted into a separate local directory and its app signature validated successfully. A loose `.app` inside this workspace receives automatic File Provider Finder metadata, so the ZIP is the supported delivered artifact.

## Native UI checks

The launched app presents its empty state, toolbar, and native Open panel. **⌘O** opens the picker. Opening `Capsule.ds3` displays the blue shaded geometry and reports **1 part, 3 nodes, 80 triangles**. Opening `Sword.ds3` displays distinct blade, guard, and handle colors and reports **5 parts, 18 nodes, 320 triangles**. Wireframe toggling displays the triangle edges. Pointer dragging and arrow keys rotate the camera, scrolling changes the camera distance, and Fit Model resets the camera. Mesh generation and document errors are covered by the automated loader tests.

The viewer remains a read-only procedural geometry prototype. Texture baking/display, embedded GLB geometry, rig/animation playback, editing, saving, and export are not implemented. Image assets produce an untextured preview warning; embedded geometry fails explicitly. In-progress C++ generation cannot be interrupted, and hostile-document process isolation/fuzzing remain future hardening work.
