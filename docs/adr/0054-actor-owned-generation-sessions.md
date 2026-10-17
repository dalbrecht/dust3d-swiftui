# ADR 0054: Actor-owned native generation sessions

Status: accepted for the prototype

## Context

Reviewed core PR #24 adds bounded generation sessions. The SDK currently exposes
stateless loading, and editor preview adoption should be independently reviewable
from native ownership and dependency changes. Borrowed C pointers must not cross
Swift concurrency boundaries or outlive their owner.

## Decision

Pin merged core revision `d691a7feb1718874b3cef0d9c843af961a252b42` and add a
`MeshGenerationSession` actor to Dust3DKit. It owns one opaque C session and
returns copied Sendable indexed geometry with immutable per-call statistics.
No native pointer is public or retained by an output value.

Store the native handle inside the existing system `OSAllocatedUnfairLock` API.
Its `uncheckedState` initializer permits the opaque non-Sendable C handle, but
all access and destruction stay inside synchronous lock regions. The immutable
lock is Sendable, so nonisolated actor deinitialization can safely release the
owner without an unchecked Sendable declaration or pointer-to-integer encoding.
This lock is a lifetime boundary, in addition to actor isolation and the native
engine's process-wide serialization. The system API is already used by the
editor save boundary and does not change the macOS 14 deployment baseline.
Alternatives were a custom unchecked Sendable owner, newer synchronization or
isolated-deinit APIs, and explicit-close-only ownership; these weaken the current
standards, compatibility or deterministic cleanup.

Share indexed conversion, copying and diagnostic helpers with stateless loading.
Release the expanded source immediately after native indexed conversion, before
allocating Swift copies; release the indexed owner after copying every buffer.
Keep all existing stateless APIs and app preview behavior compatible.

The core-defined cache budget defaults to 64 MiB, accepts zero to disable
retention, and rejects values above 256 MiB. Validate negative Swift budgets
before C conversion. Indexed output has a separate budget whose zero still
selects the existing 256 MiB default. Neither budget is a process-memory ceiling.
A cache-only failure returns valid output with its original cache diagnostic.
A primary failure throws the original loading error; statistics remain queryable.
An indexed conversion budget failure does not invalidate a successfully generated
native component cache.

Only explicit native NO_GEOMETRY becomes a nil mesh. Reset releases retained
state and clears statistics while keeping the configured limit. Cancellation is
checked before generation, before indexed conversion and after copying/statistics;
it does not interrupt C++ generation already in progress.

## Consequences

The wrapper can be tested without launching an app. Editor preview actor adoption,
encoding/coalescing, cache diagnostic presentation and source provenance follow
in separate reviewed stages. The two app entry points remain unchanged here.
Full M3 acceptance, Qt differential baselines and performance budgets remain open.

See [verification and remaining limits](../swift-generation-session-verification.md).
