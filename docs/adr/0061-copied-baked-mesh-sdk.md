# ADR 0061: Copied baked mesh SDK output

Status: implementation in progress, Apple issue #123. Core PR #40 is merged at
`2703a17ce4c1f8d21a30b23580b45520ef49c87b`; SwiftPM pins that exact revision.

## Ownership and topology

Add typed Sendable RGBA8 image inputs/options and immutable copied map/tangent
output to Dust3DKit. Keep expanded geometry for this stage: existing IndexedMesh
sharing keys only position/normal/color, so attaching per-corner UV/tangent data
to those shared vertices would erase texture/material seams. A later reviewed
indexing change must include every textured attribute or remap corners explicitly.

Validate native counts, map dimensions/row strides, tangent validity and logical
byte accounting before copying. Retain the baked owner until geometry, metadata,
pixels and tangents are copied; destroy it on success or any thrown error. No
native pointer appears in public Swift output. Retained immutable NSData input
storage pins decoded pixels only throughout the synchronous C call; descriptor
validation happens before bridging storage. No external dependency is introduced.

## Concurrency direction

The low-level loader is synchronous and must be called off the main actor.
MeshBakingService runs it on a background actor. A checked Sendable token owner
uses the macOS13+ OSAllocatedUnfairLock container to synchronize cancel/destroy
without introducing a custom unchecked Sendable conformance. The foreign pointer
is stored through the system container's uncheckedState initializer because C
explicitly permits atomic cancellation concurrent with loading. The pointer never
returns from a Sendable lock closure: cancel/close return Void, and only the actor's
local operation borrows it. The actor defers close until loading/copying finishes;
late handlers see nil. Deinitialization also closes idempotently.

A narrow internal synchronous operation protocol separates the native boundary
from orchestration. A test gate signals entry, then waits while the caller cancels;
it checks the actual C token before calling the real loader. No fake geometry,
error-injection switch or custom unchecked conformance is used. Concurrent token
cancel/close and active-request/pre-cancelled Task tests pass under Swift 6 and
Thread Sanitizer.

Native diagnostics remain typed MeshLoadingError values with their original
status/cause; Swift cooperative cancellation checks can throw CancellationError.
Resource quotas exclude Swift copies and native temporary workspace. Generation
observes phase boundaries; this is not a hard memory/latency guarantee.

## Current evidence and remaining gates

Failing-first SDK tests initially reported missing MeshBakeOptions/loadBaked.
The implementation now passes 12 focused tests covering real Capsule/Sword/
RoundedCrossing copies, padded RGBA rows, straight alpha, material maps,
malformed native views, identities/aliases, resource budgets and cancellation.
Full make ci passed 568 tests and all enforced coverage/linkage/bundle gates.
The mesh SDK measured 1214/1230 covered lines (98.70%). See
[verification](../swift-baked-mesh-verification.md) for scope and remaining gates.
Automated review and CI on the published commit remain required before merge. Initial sandboxed
SwiftPM planning intermittently failed reading the present pinned tree; the same
build with authorized dependency-cache access compiled and ran the targeted tests.

This stage does not decode archive assets, change app UI/rendering, implement PBR,
transparency/AO or textured export, or establish full M3/M4/editor parity.
