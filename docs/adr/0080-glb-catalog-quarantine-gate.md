# ADR 0080: Refuse the quarantined GLB material catalog before SwiftPM compiles it

Status: Proposed consumer gate for [core #69](https://github.com/dalbrecht/dust3d-core/issues/69).
The experimental C API remains blocked in core #67.

## Context

The unfinished GLB material-catalog C API still terminates the process with an
uncaught `std::bad_alloc` after the narrow JSON parser ownership fix. Another
exception handler cannot contain termination if allocation fails again during
unwinding. The implementation stays quarantined. Core CMake rejects its
restoration, but SwiftPM does not execute CMake. This package compiles
`dust3d-core` from the reviewed checkout.

## Decision

After dependency resolution and before `swift build` or `swift test`, scan
`$DUST3D_BUILD_ROOT/build/checkouts/dust3d-core` and fail closed unless all of
the following hold:

- `native/Engine/include/Dust3DBridge.h` exists and does not declare
  `dust3d_glb_material_catalog_` or `Dust3DGlbMaterialCatalog`.
- `native/Engine/GlbMaterialCatalog.cc` is absent.
- `Package.swift` and the root `CMakeLists.txt`, when present, do not name that
  implementation file as a source. A complete negative CMake existence guard
  whose only body is `message(FATAL_ERROR ...)` may name the file; its diagnostic
  does not compile it. All other filename occurrences remain conservatively
  rejected, including source entries after a guard or inside a compiling guard.

`Package.swift` and `Package.resolved` stay on the reviewed core revision. This
gate does not restore the API, run allocation-failure probes, or change the pin.

Re-enablement remains a separate reviewed core change with the bounded worker
protocol in core ADR 0025: parent-owned persistence, partial-result rejection,
typed failures, and no automatic retry of crashing inputs. Removing either gate
requires that review, green CI, and explicit acceptance.
