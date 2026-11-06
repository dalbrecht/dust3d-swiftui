# ADR 0160: Checked template draw copies in an isolated candidate

Status: Local experimental adoption, M5 #144 and core #319; UI integration pending.

The production core pin remains48b0ce2d. New template geometry is available only
in the local core branch. Compile the Swift adapter/tests only with
MOTE3D_EXPERIMENTAL_RIG_TEMPLATE and use script/local_core_integration.py to
record that feature in the isolated identity. The script preserves the source
Package.resolved, verifies the exact edited core and checks source identity after
execution. No second native implementation is added to the Apple repository.

Load only verified bundled XML, retain exact byte identity from the existing
bounded hierarchy reader, and parse Float32 coordinates as in Qt BoneNode.
The Qt XML loader leaves capsule radius zero. Reject missing/duplicate coordinate
elements, non-finite values and values beyond the portable coordinate bound.
Borrow contiguous input name bytes only within the synchronous C call. Copy every
native name and draw record before deferred destruction. Check source name order,
counts, logical output charge, finite values, roles and indices before returning
an immutable Sendable value. Exact Unicode spellings remain distinct.

Task cancellation is checked before loading, before publication and periodically
through copying. The native helper is synchronous and does not become an
interruptible generator. UI callers must schedule it off the main actor and
reject obsolete results; that lifecycle and Metal presentation remain subsequent
work. No actual rig, pose, skinning, weights or animation is generated here.

Validation is scoped to the new template math and buffer ownership. It does not
run quarantined pose/animation/GLB/writer or broad rejected runtime inventories.
Physical rendering and keyboard/VoiceOver acceptance remain outstanding. No
production dependency update, full Qt parity or HIG acceptance is claimed.
