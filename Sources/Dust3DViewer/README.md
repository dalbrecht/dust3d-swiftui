# Native Dust3D viewer

Standalone SwiftUI/Metal macOS app for opening existing `.ds3` documents without
Qt. Build/run with `./script/build_and_run.sh`; validate with `make ci`. The root
SwiftPM manifest defines all dependencies; no separate Xcode project or runtime
configuration is required.

Open a document with the toolbar or File menu. Drag to orbit, scroll to zoom,
use Fit Model to reset the camera, and toggle Wireframe to inspect triangles.
Ordinary geometry appears before background material preparation. Color,
normal, metallic, roughness and emission maps use bounded preview resolution.

A single bounded file snapshot supplies geometry and baking, so a later file
change cannot mix old geometry with new assets. Optional material failures keep
ordinary geometry and show the original diagnostic with Retry Materials. Closing
the view cancels pending work; late results cannot restore a closed preview.

See `docs/native-material-viewports-verification.md` and ADR 0065 for tests,
native acceptance and remaining AO, transparency and full-parity limits.

Compatibility notices follow the representation being displayed: successful image
baking removes obsolete untextured-image text; geometry/GPU fallback restores its
original notice. Legacy surface limitations and source interpretation failures
remain explicit. Metadata is prepared from the same file snapshot off-main.

## Build diagnostics

The About window reports the source revision/digest, dirty state and exact core pin
embedded in the loaded executable, separately from process identity. The startup
capture remains fixed if an on-disk bundle changes. Use the canonical build wrapper
to embed metadata; direct SwiftPM builds show unavailable identity honestly.
See [ADR 0071](../../docs/adr/0071-immutable-runtime-build-identity.md).
