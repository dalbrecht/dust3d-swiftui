# Dust3D

## Native macOS apps (SwiftUI, no Qt)

This repository now includes a native SwiftUI/Metal viewer backed by the existing C++17 engine. Build and launch with `./script/build_and_run.sh`; use `make ci` for native verification. See [native/README.md](native/README.md) for document support, architecture, and coding standards. The separate editor runs with `./script/build_and_run.sh --editor` (or `make run-editor`). It opens/saves `.ds3` documents and supports node selection, front/side dragging, coordinate/radius edits, and undo/redo. See [editor usage](Sources/Dust3DEditor/README.md). The Qt application remains available below as the original implementation.

The Swift `Dust3DKit` module provides `MeshLoader.loadIfPresent(data:)`: it returns
nil only for the reviewed core's successful no-geometry result. Other failures
retain their original status/diagnostic; `load(data:)` keeps its strict nonempty
contract for existing callers. The editor uses request-checked empty completion
to clear removed geometry while retaining stale output on genuine failures.

`MeshLoader.loadIndexed(data:maximumPayloadBytes:)` provides immutable, Sendable
vertices and UInt32 triangle indices with copied metadata. Its optional companion
returns nil only for successful no-geometry. The budget covers native exported
payloads, excluding generator workspace and Swift copies; zero uses 256 MiB.
See [indexed mesh verification](docs/swift-indexed-mesh-verification.md).
Both apps now upload unique vertices and UInt32 indices to Metal; expanded SDK
and viewport callers remain supported. See [renderer verification](docs/indexed-metal-verification.md).

`MeshGenerationSession` is an optional background actor for bounded core cache
reuse. `generateIndexed(data:)` returns copied optional geometry and cache stats;
`statistics()` and `reset()` inspect or clear retained state. Cache zero disables
retention, while indexed-output zero retains its 256 MiB default. Cache-only
issues remain distinct from primary errors. See [the ownership decision](docs/adr/0054-actor-owned-generation-sessions.md).
The editor uses document-scoped sessions; the viewer remains stateless. See
[session verification and limits](docs/swift-generation-session-verification.md).

`generateSourcedIndexed(data:)` optionally adds copied source identities, corner ranges
and complete weights while preserving cache reuse. Unknown/ambiguous/future kinds
are explicit; identities are strictly decoded without normalization. Corner ordinal
matches triangle-index position, not unique vertex index. Source/index/cache budgets
remain separate. The editor's metadata/picking adoption follows separately. See
[source hint contract and verification](docs/swift-source-hints-verification.md).

Dust3D is a cross-platform 3D modeling software that makes it easy to create 3D models for video games, 3D printing, and more. It features built-in rigging, procedural animation and UV unwrapping, with export to GLB and FBX formats.

For more information, visit [dust3d.org](https://dust3d.org/).

## Getting Started

These instructions will get you a copy of Dust3D up and running on your local machine for development and testing purposes.

### Prerequisites

- Qt 6 (recommended) or Qt 5, with the following modules: qtbase, qtsvg, qtmultimedia
- C++ compiler with C++17 support

#### Windows

1. Download and install the `Qt Online Installer`
2. Run the installer and choose the Qt 6 archives you want to install (required: qtbase, qtsvg, qtmultimedia)
3. Install Visual Studio 2022

#### macOS

1. Install Qt via Homebrew: `brew install qt`
2. Install Xcode Command Line Tools: `xcode-select --install`

#### Linux

1. Install Qt 6 using your distribution's package manager:
   - Ubuntu/Debian: `sudo apt install qt6-base-dev qt6-svg-dev qt6-multimedia-dev libgl-dev`
   - Fedora: `sudo dnf install qt6-qtbase-devel qt6-qtsvg-devel qt6-qtmultimedia-devel`

### Building

1. Clone the repository
```
git clone https://github.com/huxingyi/dust3d.git
```

2. Build using qmake

#### Windows

1. Open the Qt Creator IDE
2. Select "Open Project" from the File menu
3. Navigate to the project directory `dust3d/application` and open the `.pro` file
4. Select the desired build configuration (e.g. Debug or Release) from the dropdown menu at the bottom left of the window
5. Click the "Run" button to build and run the project

#### macOS / Linux

1. Change to the project directory `dust3d/application`
2. Run `qmake` to generate a Makefile
3. Build the project using `make`

### Releasing

1. Make sure all changes are merged to master branch including CHANGELOGS update
2. Run `git tag <version>` (e.g. `git tag 1.1.0`)
3. Run `git push origin <version>`
4. Wait for Actions/release to finish and download all the Artifacts
5. Go to `Tags/<version>` and create release from tag
6. Title the release as `<version>`
7. Copy description from CHANGELOGS
8. Drag the Artifacts to binaries: `Dust3D-win32-x86_64.zip`, `Dust3D-x86_64.AppImage`, `Dust3D.dmg`
9. Publish release

## License

Dust3D is licensed under the MIT License - see the [LICENSE](https://github.com/huxingyi/dust3d/blob/master/LICENSE) file for details.

<!-- Sponsors begin --><!-- Sponsors end -->
## Native product roadmap

The native viewer is a standalone read-only app. The editor is a separate SwiftUI app sharing the pinned Qt-free engine and Metal renderer. The initial graph-editing slice is implemented; full modeling parity remains planned. See the [full editor implementation and repository restructuring plan](docs/editor-port-plan.md), including the proposed split into Apple UI and portable core repositories.
