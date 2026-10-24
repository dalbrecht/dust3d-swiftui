# Dust3D native engine and viewer

A Qt-free C++17 modeling engine, a narrow C ABI, a Swift document service, and a read-only SwiftUI/Metal viewer for existing `.ds3` documents. Requires macOS 14+ and Xcode with Swift 6+; development is verified on Apple Silicon.

From the repository root:

```bash
git submodule update --init .standards
make ci
./script/build_and_run.sh
```

Open a `.ds3` with the toolbar or **File → Open… (⌘O)**. Drag to orbit, scroll to zoom, toggle wireframe, or use Fit Model to reset. The viewport supports arrow keys and F for camera fitting. Each window owns its mesh and loading state. File errors retain the previous successfully opened mesh.

Use `Tests/Dust3DKitTests/Fixtures/Capsule.ds3` as a small existing-format sample; it is produced by the repository's independent Python `.ds3` writer from the adjacent XML. The existing agent-modeling tools can also generate more complex documents from JSON examples.

`Package.swift` is the build specification and pins the external `dust3d-core` source package to an exact revision. `Package.resolved` is committed. The Apple repository no longer carries a second native C ABI implementation; standalone engine builds and SDK packaging belong to the core repository. `make build` compiles the engine and app. `make test` runs the document-loading tests with coverage. `make lint` checks new Swift/C++ formatting and shell syntax. `make check-qt-free` checks native sources and the executable's dylib/framework linkage. `make sync-standards` assembles Codex instructions from the pinned standards while preserving project supplements.

`script/build_and_run.sh` builds and ad-hoc signs the app in the local build directory, launches it, and delivers `dist/Dust3DViewer.zip`. Extract the ZIP into a fully local folder, such as `/Applications`, before launching: File Provider folders can add Finder metadata inside app bundles that invalidates signatures. The script supports `--build-only`, `--verify`, `--debug`, `--logs`, and `--telemetry`; `--build-only` prints the runnable app path. The Codex Run action calls the same script. `script/swift.sh` keeps compiler caches outside cloud/File Provider checkouts, where object files and module caches must remain materialized. Its default cache identity uses the canonical Git common directory, so linked worktrees share one temporary root. Source archives or unavailable Git metadata fall back to the canonical source directory; unrelated repositories remain separate. Override the location with `DUST3D_BUILD_ROOT` to reuse one existing root across repositories as well. Run only one build against that root at a time. UI test captures default to `$DUST3D_BUILD_ROOT/ui-qa`; `DUST3D_UI_QA_OUTPUT_DIR` preserves an explicit evidence destination. Capture names are reused, so preserve review evidence before another run. This is artifact output, not a visual baseline. Existing caches/evidence are neither migrated nor deleted automatically. It selects SwiftPM's native builder to work around this host's Xcode 27 Swift Build test-bundle signing failure. The native builder is currently deprecated by SwiftPM; revisit that workaround on toolchain upgrades.

Procedural mesh geometry and vertex colors are supported. Image textures, texture baking, reference images, embedded GLB imports, rig/animation playback, editing, saving, and export are later milestones. Documents containing imported GLB geometry fail explicitly. Textured documents show a compatibility warning with an untextured preview. Model generation runs off the UI thread but cannot yet be interrupted inside C++.

See [architecture](../docs/adr/0001-native-engine-and-viewer.md), [standards audit](../docs/coding-standards-audit.md), and [verification](../docs/native-viewer-verification.md).
