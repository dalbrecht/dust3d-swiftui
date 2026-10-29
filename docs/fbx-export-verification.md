# Original procedural FBX verification (#286)

## Source and fixture scope

Core is the unchanged reviewed 48b0ce2d revision. Static inspection covered
FbxExportBridge.cc, DocumentReader.cc, Dust3DBridge.cc original-export preparation,
FbxGeometrySelection and FbxMeshScene. GEOMETRY mode supplies no imported owner,
UV/bake output or rig/animation evaluator. This does not claim that every linked
engine dependency excludes rig code: mesh_generator.cc has an inherited rig
header include without an invocation in the audited path.

NativeFBXExportIntegrationTests uses only the existing licensed Capsule fixture,
freshly built Swift binding and GEOMETRY mode. It checks the binary container,
owned copies surviving later owner destruction and unchanged fixture bytes.
The optional DUST3D_FBX_QA_OUTPUT_DIR writes FBX and the existing healthy OBJ
reference to an already-created caller-owned verification directory. It is not
an application export destination or a new input format.

## Independent consumer

The installed Assimp 6.0 importer successfully read the 9706-byte FBX. No new
consumer dependency is required by app builds or CI. Reproduction after creating
an owned directory under the one shared build root:

```sh
DUST3D_FBX_QA_OUTPUT_DIR="$DUST3D_BUILD_ROOT/fbx286-output" \
  ./script/swift.sh test --filter NativeFBXExportIntegrationTests
assimp info "$DUST3D_BUILD_ROOT/fbx286-output/CapsuleGeometry.fbx"
assimp dump "$DUST3D_BUILD_ROOT/fbx286-output/CapsuleGeometry.fbx" \
  "$DUST3D_BUILD_ROOT/fbx286-output/CapsuleGeometry.assxml"
assimp dump "$DUST3D_BUILD_ROOT/fbx286-output/CapsuleGeometry.obj" \
  "$DUST3D_BUILD_ROOT/fbx286-output/CapsuleReference.assxml"
```

| Observation | Fresh output |
| --- | --- |
| FBX container | Binary, 9706 bytes |
| Imported geometry | One triangle mesh; 80 faces; no bones or animation channels |
| Unprocessed importer vertices | 240 corner positions; 42 unique referenced positions |
| Independently imported OBJ | 42 unique referenced positions; 16 triangles and 32 quads |
| Bounds | (-0.16, -0.31, -0.16) through (0.16, 0.31, 0.16) |
| Normals | Finite, unit squared length within 0.00001 |
| Quad planarity | Maximum distance about 9.04e-18; admitted tolerance 0.000002 |
| Geometry comparison | All source polygons matched by oriented FBX triangles, preserving multiplicity and referenced positions to six decimal places |

The initial direct triangle-set comparison correctly failed because raw OBJ
preserves quads. Explicit Assimp triangulation then produced 80 triangles but
selected different diagonals for the planar quads. The final comparison retains
orientation: canonicalize each triangle by cyclic rotation only, match each
original triangle or one of the two oriented splits of each proven-planar quad,
subtract matched triangle multiplicities and require no unmatched FBX faces.
Vertex indices are checked in bounds; all positions and normals must be finite;
referenced position sets and bounds must match. This avoids treating incidental
index order, corner splitting or planar-quad diagonal choice as changed geometry.
Assimp adds a DefaultMaterial during import; this is not exported material parity.

This is one ordinary static fixture, not general consumer, large-model, textured,
rigged/animated or Qt export acceptance. No malformed-native, allocation/fault,
pressure, native-cancellation or crash probes are added. Core #67/#69, #83, #84,
#95 and Apple #199 remain quarantined.

## UI review

Mode: full; scope: shared native geometry export menu, format-specific activity,
completion/warning and chooser admission. SwiftUI system controls, semantic
colors, SF Symbols and the existing narrow NSSavePanel boundary are retained.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | Actual 640-point light/dark ready, choosing, encoding, cancelling and long-file completion/warning renders | Clear; middle-truncated filename, full path help and wrapping warning retained |
| Surfaces | Source and rendered menu, Cancel and Dismiss labels | Clear; minimum 40-point label height, native menu and existing divider |
| Animations | Source and static loading/cancellation states | No custom motion; native progress timing not verified |
| Icons | Existing export/checkmark SF Symbols and disabled/loading states | Clear in scoped samples |
| Performance | Actor encoding, synchronous copy lifetime and shared task/chooser ownership; injected tests | Clear source/test scope; live export/UI latency not verified |

Resolved changes:

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | Sources/Dust3DEditor/Views/EditorGeometryExportStatusView.swift:15 | OBJ-only activity/cancel/result labels | Captured format and receipt format in labels | State feedback must describe the selected export |
| LOW | Sources/Dust3DEditor/Views/EditorGeometryExportMenu.swift:14 | One OBJ toolbar button | One native menu with both named formats and a 40-point label | Keep discovery concise without duplicating busy controls |

Considered but rejected:

| Location | Candidate | Rejected because |
| --- | --- | --- |
| Toolbar | Separate OBJ and FBX buttons | Adds repeated chrome for one shared task/chooser |
| Status | Custom success/format transitions | Native static state and text already communicate completion; extra motion distracts |
| Hidden render | Force accent styling | Would misrepresent inactive native controls |

GeometryExportRenderingTests renders actual controls in a hidden test-owned
window with prohibited activation and asserts zero export callbacks. Ten sample
PNGs are exported only through DUST3D_UI_QA_OUTPUT_DIR. No local baseline is
committed. The native panel type/extension policies and fake publication workflows
pass; live panels, menu selection, Command-Shift-E dispatch, keyboard focus,
VoiceOver, physical hit testing and supported OS matrix remain not verified.

No actionable interface-polish findings remain in the inspected scope.
Verdict: Approve for source/offscreen scope only, with the live checks above open.


## Local gate

Full `make ci` passed: 45 build-support tests, 1100 XCTest cases with zero failures
(149.784 seconds) in the initial gate, strict formatting/build, all measured coverage gates, Qt-free
app/extension linkages and isolated bundle rebuild/signature checks. The QA bundle
reuses its existing identity and is not launched. Sources stayed frozen until the
gate terminated. Subsequent README edits only clarify format-specific scope.
A subsequent fake error-banner regression closes the localized diagnostic presentation gap;
the final full gate is recorded with the public PR. Fifteen new XCTest cases cover this stage; failure/cancellation inputs use
injected operations, never the quarantined foreign paths. Public exact-head review
and all remote CI remain the merge gate.


The final full gate, including the error-banner regression, passed 45 support
and 1101 XCTest cases with zero failures (124.530 seconds), all coverage checks,
Qt-free linkage and isolated bundle/signature verification. Error presentation
is tested with injected typed causes, preserved source bytes and no destination
publication. Line coverage does not prove foreign rejection, pointer/fault,
physical panel or accessibility acceptance.

Final scoped coverage (line coverage is not branch/foreign-failure evidence):

| Source | Lines | Regions | Functions |
| --- | --- | --- | --- |
| NativeFBXExportEncoder | 82/82 (100%) | 38/41 (92.68%) | 10/10 |
| NativeGeometryExportEncoder | 14/14 (100%) | 7/7 | 3/3 |
| EditorGeometryExportWorkflow | 121/125 (96.8%) | 45/53 (84.91%) | 19/19 |
| EditorGeometryExportPhase | 6/6 (100%) | 5/5 | 1/1 |

The native owner/accessor rejection branches remain unexercised by the ordinary
positive, and are not justification for fault or invalid-pointer probes.
