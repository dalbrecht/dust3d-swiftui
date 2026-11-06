# ADR 0160: Checked template draw copies in an isolated candidate

Status: Local experimental adoption, M5 #144 and core #319; native template preview locally implemented; physical acceptance pending.

The production core pin remains48b0ce2d. New template geometry is available only
in the local core branch. Compile the native-loading adapter and preview only with
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
interruptible generator. The preview schedules it off the main actor and rejects obsolete results through
its surface-owned publication epoch. Physical lifecycle/rendering acceptance
remains outstanding. No actual rig, pose, skinning, weights or animation is generated here.

Validation is scoped to the new template math and buffer ownership. It does not
run quarantined pose/animation/GLB/writer or broad rejected runtime inventories.
Physical rendering and keyboard/VoiceOver acceptance remain outstanding. No
production dependency update, full Qt parity or HIG acceptance is claimed.

The template browser now hosts MeshViewport with complete tapered solids/rings.
A surface-owned observable state starts an independent background worker for each
exact source/selected-name request and palette. Template generation and role-color copying stay off the main actor. The existing
renderer keeps its normalization, GPU setup and rendering on the main actor. Every request gets a UUID epoch, so
A-to-B-to-A cannot admit an old equal request or late GPU error. Replacement,
caller cancellation and disappearance cancel workers and reject publication.
Separate surfaces share no mutable state. Successful no-template output is
separate from failures retaining the original diagnostic; Retry starts a new
structured view task. Platform system green/accent colors stay outside the core.
The native View menu exposes all orbit/pan/zoom actions and Fit without requiring
pointer gestures; the selected template name is also text, independent of color.
The existing document/assignment state is not mutated by preview interaction.
Physical rendering, pointer/keyboard and VoiceOver acceptance are still open.

Pure draw values and role-color copying are compiled in standard builds and have
ordinary Swift-only contracts. Only the new native calls and preview are behind
the experimental flag. This keeps every mesh-library source represented in the
unchanged production coverage gate; no conditional coverage exclusion is added.

Palette resolution follows both colorScheme and colorSchemeContrast, choosing
Aqua/Dark Aqua or the corresponding accessibility high-contrast appearance.
The request key includes resolved color values, so a palette change cancels the
old preparation and starts a new publication epoch. The four-way appearance-name
contract is tested without opening a view or inspecting an existing application.
Physical contrast and VoiceOver acceptance still require separate evidence.
