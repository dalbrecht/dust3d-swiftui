# ADR 0165: Generated hierarchy and read-only joint inspection

Status: Experimental local-core integration, Apple #367 / M5 #144.

The M5 plan calls for hierarchy/property inspection. Keep template browsing and
assignment actions distinct from actual generated joints. Qt's source-order tree
in application/sources/bone_manage_widget.cc629-653 is built from template
m_rigStructures, not a separate actual-joint tree. Its bone_property_widget.cc17-38
only exposes the document eyelid checkbox. This native actual-joint hierarchy and
numeric inspection is not a literal port of a missing Qt numeric property panel.

GeneratedRigHierarchy derives an immutable forest from resolved parent indices.
Use original source Int indices as IDs; names, geometry, placement and Unicode
canonical equivalence never determine membership. Preserve forward references,
multiple roots, root/sibling source order, zero-axis joints and appended eyelids.
Reject invalid parents/self links and disconnected cycles rather than applying
Qt's template missing-parent fallback. Limit to256 joints matching the Swift copy
boundary. Iterative component traversal/postorder construction avoids recursive
building; leaves use nil children and empty input has no roots. Poll cancellation.

Prepare this metadata in the detached generation worker from the copied rig.
Publish it with that rig under the current generation epoch. A metadata error
retains the original diagnostic in hierarchyError and preserves the copied rig;
cancellation remains cancellation and cannot publish a partial rig. Replacement
and stop clear metadata. Keep hierarchy/properties outside the GPU-error branch.
The OutlineGroup uses source IDs and the same source/epoch-guarded selection as
the flat picker, preserving camera identity during selection/appearance changes.

Read-only properties show parent, grounded endpoints, length, capsule radius and
signed closing angle. Linear values are model units, not meters. Convert Float
components to Double before subtracting/length calculation. Angles are radians
in core: dust3d/rig/rig_generator.cc2088-2104 uses acos and retains upper-negative,
lower-positive eyelid direction; source-only inspection of animation/common.h1345-1349
and base/quaternion.h114-120 confirms direct sin/cos(angle/2) usage. Display degrees
with an explicit label; do not clamp or evaluate a pose. Source unit audit does
not execute animation. Eyelid append order/Head parent is recorded at1972-1988.

TDD missing API RED98368, then GREEN15100:60 focused tests. Measured hierarchy
70/70 lines48/48 regions6/6 functions; metrics7/7 lines2/2 regions/functions;
generation state117/117 lines41/41 regions12/12 functions, all100%. Fixtures are
small copied Swift values: source ordering/forward parents/Unicode/zero axes and
four eyelids, invalid indices/cycles, a flat256/257 boundary, unit arithmetic and
cancellation. No depth, stack or allocation-exhaustion probe. Metadata failure is
isolated and obsolete work rejected; injected builder cancellation is propagated.
Independent source review found no concrete defect. Strict formatting passes.

Experimental complete-UI compilation and full production make ci remain pending.
No new GUI, native generation, pose/controller, animation, GLB/writer or broad core
catalog probes are introduced by these tests. Physical HIG/keyboard/VoiceOver and
actual rendered hierarchy acceptance remain open. Production pin48b0, QA52,
protected QA process and all quarantines remain unchanged; coree63 is local only.
