# ADR 0168: Copied-data generated bone picking

Status: Experimental local-core integration, Apple #367 / M5 #144.

Native M5 explicitly requires skeleton visibility/picking (editor-port-plan168).
Qt ModelWidget defaults mouse picking off (model_widget.h96); BoneManageWidget
creates both previews without enabling it (bone_manage_widget.cc177-196), and its
selection synchronization is tree-based (565-586). This delivers native-plan
picking rather than claiming a literal port of enabled Qt bone picking.

Carry original source-joint indices per skeleton triangle, retaining gaps for
zero-axis joints. Reject partial triangles, out-of-range indices and mixed-owner
triangles in copied metadata. The body follows the skeleton prefix and has no
bone owner. Publish the display mesh, boundary, weight summary and optional
picking geometry under the same accepted display key. Picking metadata is derived:
its original failure is displayed without discarding valid rendering/inspection.
Cancellation never publishes partial preparation. Native visualization remains in
the existing GENERATED flag; these helpers do not generate a rig or evaluate pose.

MeshPickingGeometry shares the full immutable Mesh buffer and RenderBounds frame.
It does not filter bounds or allocate another normalized vertex stream. Pointer
coordinates are bottom-left view points, not backing pixels; the camera matrix
uses the same actual drawable aspect as the renderer. Unproject Metal clip depth
zero and one, map the near/far segment into source space, and test two-sided
triangles in Double. Restrict hits to the visible draw span, reject behind/near/far
and nonfinite input, and choose the nearest triangle with stable source-order
ties. A body hit blocks selection; hide Model for interior bones. This geometric
surface policy applies independently of the Wireframe style. It is not pixel
readback or an assertion of completed physical interaction acceptance.

Prepare bounds and trace on a cancellable worker, polling long loops. Preserve
selection on miss/body/error. A valid bone hit only updates the read-only joint
highlight, never document assignment or Undo history. Each request captures its
source/display/presentation/visibility pick UUID, camera input UUID and job UUID;
completion rechecks current actor-owned snapshot/readiness before publication.
Explicit selection, source replacement, display changes, visibility, presentation,
controls and stop invalidate old work. Newer clicks replace older workers.

Opt-in input records a pending press. Movement under four view points can finish
as a click; threshold crossing becomes irreversible drag with the full initial
delta followed by incremental deltas. Accepted camera movement invalidates pending
clicks, while the drag's own camera changes do not stop subsequent deltas. Source
lease changes, scroll and keys clear pending input. Resize and backing changes
invalidate the ignored projection epoch without moving the camera, rejecting old
background hits and pending gestures. Defaults with no picking callback preserve
ordinary immediate-drag behavior.

The Metal surface remains hidden from accessibility; the existing hierarchy and
Weight highlight picker provide joint selection by keyboard. Visible status/help
explains background work, misses, body occlusion and original failures. Pure copied
geometry and gesture/epoch tests validate logic without NSView, NSEvent, Metal
devices or native generation. Physical layout/GPU/pointer/keyboard/VoiceOver and
whole local-core modeling acceptance remain open. Pose/animation and all existing
quarantines remain unchanged; production core pin stays fixed.
