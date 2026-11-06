# ADR 0162: Grounded generated-rig rest preview geometry

Status: Experimental local-core integration; Apple #367 / core #330 / M5 #144.

GeneratedRigSkeleton is distinct from normalized template browsing geometry.
Its native factory validates all source joints, omits exactly zero axes from
visualization input, disables native normalization, copies checked buffers before
owner destruction, and remaps filtered bone indices to full source order. All
joint names remain available, including unplaced joints and derived eyelids.
The factory uses the existing bounded visualization bridge, not pose evaluation.

GeneratedRig.previewMesh assembles skeleton first and grounded body second in
one raw coordinate frame. The ordinary RenderGeometry transform then computes
one combined bound. Skeleton colors use the platform palette with alpha one.
The body matches Qt RigSkeletonMeshWorker: selected-name weight sums all four
slots, positive weight is red-to-blue, unweighted vertices are gray, alpha 0.8.
Names use exact UTF8 correspondence. Invalid mapping and cancelled work fail.

Expanded MeshViewport accepts explicit blendsVertexAlpha, default false. The
Metal pass uses source-alpha/one-minus-source-alpha factors for RGB and alpha,
retains less/depth-write testing, and preserves vertex alpha only when opted in.
Ordinary indexed/material routes remain opaque. Policy changes invalidate the
renderer and receive fresh UUIDs, so a false/true/false transition cannot admit
an obsolete queued error merely because its policy and mesh revision match.

Validation: initial missing-API RED; ABA missing-epoch RED after a test-only Swift6
isolation correction; 39 focused production tests pass. New pure composition
coverage is 58/58 lines, 44/44 regions and 12/12 functions. Against exact clean
core e63d16f0, all14 focused tests pass, including four native visualization tests
for zero-axis gaps, byte-exact Unicode names/selection, raw frame, tiny nonzero
axes, validation and precancel. Native skeleton tests were added during factory
implementation; no separate native RED claim is made. A first isolated build
failed with disk ENOSPC before tests; obsolete completed build caches were
retired with source snapshots and identity records retained, then the identical
focused run passed with source identities guarded before/after.

No generated preview view is wired yet. No GUI/GPU/pose/animation/GLB/writer or
broad catalog runtime acceptance is claimed. Offline Metal compilation could
not run because the host Metal Toolchain is absent. Full make ci for this branch
and physical UI/HIG/VoiceOver acceptance remain outstanding. Production core
pin, default QA52 build and quarantines are unchanged.

Next, generation and display preparation require separate task keys: immutable
document request for generation; generated-rig UUID, exact selected-name bytes
and palette for display. Preserve viewport identity at the rig UUID, replacing
mesh revision on accepted display changes, to preserve camera state. Hide stale
colors immediately while retaining the viewport during preparation. List every
actual joint, including zero axes and derived eyelids, independently of drawable
vertices. Keep the old pose controller out of this rest-only surface.
