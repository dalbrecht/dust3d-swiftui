# Copied baked mesh SDK verification

Scope: Apple issue #123 and ADR 0061. Exact reviewed core revision:
`2703a17ce4c1f8d21a30b23580b45520ef49c87b` (core PR #40).

## Copied values and input ownership

The public low-level loader and background service return Swift-owned expanded
geometry, UV/chart metadata, triangle tangent frames and RGBA8 maps. Expanded
vertices retain seams; the existing geometry-only IndexedMesh sharing is not
reused. Native owners are released through defer after every copy or thrown error.

Twelve focused contracts exercise Capsule/Sword/RoundedCrossing output and
independence across later loads; actual padded image rows with omitted final
padding; distinct case-sensitive image identities; source alpha; real metallic,
roughness and emission values; absent optional maps; malformed views, identities,
aliases, dimensions and quotas; and known/unknown/reflected tangent frames.
Descriptor validation precedes NSData bridging. Immutable NSData storage is held
through the synchronous C call, rather than retaining a pointer obtained from an
expired Data.withUnsafeBytes closure. No native pointer appears in public output.

## Background cancellation

MeshBakingService is a background actor. A checked Sendable token owner uses the
system OSAllocatedUnfairLock container for cancel/destroy synchronization. Its
foreign pointer is borrowed only by the active operation and destroyed only after
that operation/copy finishes. Late cancellation sees nil; close/deinit are
idempotent. No custom unchecked Sendable conformance was added.

A deterministic operation gate signals entry while the MainActor caller remains
able to cancel. The gate then checks the actual C token and calls the real loader;
it does not fabricate geometry or inject an error. Other contracts cover
pre-cancelled Tasks and 100 concurrent token cancel/close operations. This proves
the handler can reach a live token independently of actor re-entry. It does not
promise arbitrary preemption inside inherited generation or a cancellation SLA.
Native failures retain their status/cause, including cancellation status 6; Swift
cooperative checks throw CancellationError.

## Full local gate

`make ci` passed: formatting/shell checks, all product builds, 568 tests with zero
failures (86.234 s test time), coverage thresholds, Qt source/link checks and
isolated bundle rebuild regression checks. Current coverage:

| Scope | Covered lines | Required |
| --- | --- | --- |
| Swift mesh library | 1214/1230 (98.70%) | 95% |
| Document library | 2918/3002 (97.20%) | 95% |
| Editor model | 1490/1496 (99.60%) | 95% |
| Pure editor state | 529/529 | 100% |
| Pure undo domain | 97/97 | 100% |
| Pure orbit camera | 33/33 | 100% |

These are measured Swift source scopes, not inherited-core/GPU coverage. Native
sources and both app linkages remain Qt-free. Bundle checks rebuilt isolated
Editor/Viewer copies and left default archives unchanged. No app UI or native
interaction was changed or manually accepted in this SDK stage.

The isolated Thread Sanitizer run passed all four MeshBakingServiceTests with
zero failures/findings (0.039 s test time). It used a separate build root so the
full-gate coverage profile remained intact.

## Remaining scope

This API consumes decoded straight-alpha RGBA8 inputs; extracting/decoding retained
archive assets follows separately. PBR/transparency/AO, editor scheduling/cache
invalidation, seam-aware indexing, textured exports and full M3/M4/editor parity
remain open. Logical quotas exclude Swift copies, caller images, native workspace
and allocator capacity. The core temporary C++ bake output also has its own 256 MiB
ceiling. No process-memory or whole-call cancellation-latency guarantee is claimed.

Initial sandboxed planning intermittently failed to read the present exact-pinned
dependency tree. Verification with authorized SwiftPM cache/network access compiled
and ran successfully; no source change or weaker test was used to mask that failure.
