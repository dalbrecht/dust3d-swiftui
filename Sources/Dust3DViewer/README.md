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
