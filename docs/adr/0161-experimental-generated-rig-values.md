# ADR 0161: Copied actual generated-rig values and actor loading

Status: Experimental local-core integration, Apple #367 / core #330 / M5 epic #144.

Add GeneratedRig, GeneratedRigJoint and GeneratedRigInfluences as immutable
Sendable Swift values. Positions and body are already grounded together; matrices
are sixteen column-major doubles. Four slots retain UInt32.max/zero unbound data.
Pure value types compile normally; useful isBound behavior has ordinary tests.
Native symbols/service are behind distinct MOTE3D_EXPERIMENTAL_GENERATED_RIG,
leaving older template-only local-core builds and the production pin compatible.
The isolated build helper admits and records the new explicit feature flag.

GeneratedRigService loads pinned template hierarchy/resources on its background
actor, keeps all UTF8 name/parent/type spans alive for the synchronous C call,
and uses the existing lock-backed native cancellation owner with task cancellation.
Count/payload/source-order exact UTF8/finite values/parent forest/four-slot bounds
and normalization are checked while the C owner is live. Mesh/joints/matrices/
names/weights are copied before defer destroys that owner. The token is closed
only after loading; cancel/close serialize. No unchecked Sendable conformance or
foreign pointer escapes. Original resource/native status/diagnostic is preserved.
Cancellation checks are cooperative, not fixed-latency preemption of all stages.

TDD feature-flag admission failed before support was added; all18 isolated-build
support tests pass. A test static fixture qualification was corrected before the
successful identity-guarded run. Four focused tests pass against exact clean core
e63d16f0: assigned Capsule actual bones/weights/rest, unbound pinned Snake, None,
original errors, precancel and independent Swift results. Focused file coverage is
263/273lines (96.34%),87/107regions (81.31%),27/29functions (93.10%). Defensive C
buffer guard/error branches remain partly unexecuted; no malformed native-owner
or failure injection is used to force coverage. No UI/pose/controller is exercised.

Production make ci passes: all1700 XCTest tests,2expected skips/no failures;
required coverage Kit3611/3669,Document6020/6173,Editor4901/4962,purestate925/925,
undo137/137,orbit43/43; formatting/build support,Qt-free and isolated signed app/
extension/archive rebuild gates pass. The main intentional AGENTS bytes and
48b0 production pin are unchanged. Full source identity stayed fixed during builds.

No actual generated-rig UI is wired yet. Next preview must capture document
identity/revision/immutable encoded bytes/rig settings plus fresh request UUID:
rig-only commands deliberately do not change ordinary mesh geometry identity.
Use GeneratedRig.mesh with its own bones, not the ungrounded store.mesh. Shared
body-derived bounds and a deliberate skeleton overlay-depth pass are needed;
separate normalization or simple opaque concatenation cannot establish overlay
parity. Keep zero-axis joints listed even when not drawable. Avoid the old #199
pose controller. Real-world rig/UV/import/export, physical GPU/HIG/VoiceOver and
full Qt parity remain open; QA52 default and all quarantines remain unchanged.
