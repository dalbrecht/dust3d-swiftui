# Mixed-material macOS preview verification

Related: #174, ADR 0084. Public review pending.

## Current integration

The current integration preserves the reviewed shared image-free representation
selection and adds confirmed-frame source-detail warning acknowledgement. A new
regression failed with the stale detail warning before wiring and passes after it;
GPU fallback restores the original warning. Current full-gate results will be
recorded in the delivery PR. Fresh native GUI/extension verification is unavailable
while the Mac is locked; no current screenshot or system-host acceptance is claimed.

## Earlier local checkpoint automated contracts (October 19, 2026)

Focused tests pass for mixed preparation, exact archive bytes and preview quotas;
source metadata and alpha policy through real Metal readback; all three public
render dispatch paths; actual material-render failure with ordinary GPU fallback;
paired original failures; request validation; and cancellation at preparation,
material and fallback boundaries. SourceMeshBakeError diagnostics cover all nine
cases. Metal tests explicitly require a device; CPU policy tests need no window.

Focused command:

```sh
./script/swift.sh test --filter 'SourceFilePreviewTests|FilePreviewRenderPolicyTests|SourceMeshBakeErrorTests|ImportedFilePreviewTests|FilePreviewDocumentTests|FilePreviewRenderingTests|MaterialViewportTests'
```

The earlier checkpoint full `make ci` passed 854 XCTest cases, 31 build-support tests,
coverage checks, Qt-link checks and bundle-rebuild checks. The fallback policy
measured 67/67 lines, 34/34 regions and 5/5 functions covered; SourceBakedMesh
measured 36/36 lines, 15/15 regions and 4/4 functions. FilePreviewDocumentService
measured 138/143 lines (96.50%), 56/60 regions (93.33%) and 29/32 functions
(90.62%). Its cancellation handler is exercised by cancelling real in-flight
preparation and then loading the next request through the same service. Remaining
loader gaps include native empty-generation boundaries and default-argument
functions; coverage is not claimed complete. This does not establish inherited
engine or whole-editor coverage.

## Earlier native macOS observations (October 19, 2026)

Built the editor bundle with `--editor --build-only`, reusing org.dust3d.editor
and its existing Quick Look/thumbnail identifiers. A public
QLThumbnailGenerator request returned representation type 2 (thumbnail), 256 by
256 pixels, showing both the teal imported surface and colored procedural surface.
Provider operation logging confirmed execution of the rebuilt thumbnail extension.
A fresh copy of MixedMaterials.ds3 also produced a thumbnail after normal editor
quit, with the editor verified absent. Fixture bytes remained unchanged.

Finder Quick Look of that fresh file displayed both surface kinds and 20 triangles.
Wireframe toggled on and off and Fit remained functional. The preview and temporary
Finder window were closed after inspection, preserving the user's existing window.
Screenshot evidence: `/private/tmp/dust3d-mixed-quicklook-native.png`;
thumbnail: `/private/tmp/dust3d-mixed-system-thumbnail-after-quit.png`.
These are local diagnostic artifacts, not portable pixel baselines.

Initial system requests failed before provider execution: targeted system logs
reported LaunchServices -10814 and missing extension records. Scoped registration
of the staged containing app followed by one normal containing-app launch restored
system requests. Force registration alone had not resolved the failure. No global
cache reset, new bundle identifiers, entitlement changes or signing weakening was
used. Static packaging checks alone do not prove system discovery or rendering.

Native integration remains a graphical-session verification step, distinct from
headless tests. Maximum sampling LOD remains zero until isolated atlas mipmaps
land; large-model packing, export and broader compatibility acceptance remain open.
