# ADR 0087: Result-owned source mip routing

Status: Local implementation under #177; public review pending. Related: #175,
#176, M4 #143 and core #59.

## Decision

SourceBakedMesh now retains SourceBakedMipmaps with explicit color, normal,
metallic, roughness and emissive roles. Each optional chain owns Swift image data;
existing native loading defaults to no chains. The source result remains an
immutable Sendable value with no borrowed native pointers. Base texture data may
share immutable Data storage with a chain; no extra pixel copy is implied by
retaining a value. The existing copied-output root charge uses the enlarged actual
SourceBakedMesh layout, so base-only exact-budget tests also exercise this change.

A pure role-to-slot transformation maps retained chains into the renderer's
established five texture slots. The default source resource builder consumes that
transformation. Remove the separate caller mip override, preventing a source result
and a side-channel set of textures from drifting apart. Viewer/editor viewports
and file previews already use the same source input and therefore inherit this
routing without additional scene state or a second rendering implementation.

Upload preflight still checks exact base correspondence, every required level,
producer LOD and aggregate GPU payload. Missing/inconsistent chains remain a
specific material failure; the public file-preview path preserves the original
cause and renders ordinary geometry rather than silently pretending mip materials
succeeded. Existing native base-only results retain LOD zero and empty chains.

## Verification and remaining adoption

Test-first typed ownership/default checks, canonical slot mapping and real pinned-
core source-copy budget tests pass. Native GPU trilinear/clamp and production-
fragment minification tests now use the default result-owned source input. The
public file-preview renderer displays retained diagnostic mip color with no
material error, and separately preserves the exact missing-chain error during
ordinary geometry fallback. Focused tests pass (27 cases). FilePreviewImage is
BGRA; the initial test's RGBA assumption was corrected against its documented
storage contract. No runtime channel conversion was changed.

An earlier local checkpoint `make ci` passed 872 XCTest cases and 31 build-support tests,
coverage checks, Qt-link checks and bundle-rebuild checks. At that checkpoint SourceBakedMipmaps
measured 7/7 lines, 1/1 regions and 1/1 functions; SourceBakedMesh measured
47/47 lines, 16/16 regions and 5/5 functions; TexturedRenderMetadata (including
the pure slot adapter) measured 68/68 lines, 37/37 regions and 12/12 functions.
These are historical file-scoped measurements, not full inherited-core/editor
coverage or current integration counts; current gate results are recorded in the PR.
Diagnostic mip colors
prove transport/sampling, not chart isolation or actual imported archive mip
production. Binding reviewed native count/level accessors, copying each unique
pixel payload exactly once, enabling native generation, procedural/mixed and
large-model visual acceptance, and textured export/re-import remain required.
Package.swift and Package.resolved keep the reviewed core revision unchanged.
No UI controls, dependencies or serialized document fields change.
