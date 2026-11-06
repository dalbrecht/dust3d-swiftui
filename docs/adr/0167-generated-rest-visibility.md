# ADR 0167: Fixed-frame generated rest visibility

Status: Experimental local-core integration, Apple #367 / M5 #144.

The Qt animation management surface exposes Bones/Model/Weights/Wireframe
(application/sources/animation_manage_widget.cc103-120,547-550); source-only
AnimationPreviewWorker.cc197-224 combines visibility geometry. This native slice
operates on copied rest data and never evaluates animation or a pose.

Keep the full skeleton-first/body-last vertex stream for normalization and GPU
upload. Filtering geometry before RenderGeometry would change bounds and shift
the camera as visibility changes. Expanded MeshViewport therefore accepts an
optional triangle-aligned draw range: nil draws all, a prefix draws skeleton,
a suffix draws body, and an empty range clears without drawing. Range updates do
not rebuild buffers or change mesh revision. Existing indexed/material APIs keep
nil/full behavior. Invalid ranges remove drawing permission before reporting their
original diagnostic. Valid ranges recover on the existing buffer; range request
UUIDs reject stale queued errors across range/source round trips.

Publish skeletonVertexCount atomically with accepted display mesh/weight summary.
The display builder appends every source body vertex after its skeleton prefix;
check full/body counts are triangle-aligned and full count is at least body count.
Retain old mesh and its old boundary together during replacement/error, but views
must require the accepted current request before using metadata. New sources and
stop invalidate the accepted pair. All-hidden and bones-only/zero-axis states
have deliberate text; hidden geometry never becomes an empty-mesh generation
failure. Camera movement is unavailable for empty spans. Numerical properties
and hierarchy remain available.

Model/Bones are presentation flags: no generation or display rebuild. Weights is
a display-key flag, separate from selectedBoneName. Disabled weights makes body
vertices gray with alpha0.8, preserving skeleton colors, selected joint and weight
summary. The full vertex positions/normals/counts and skeleton-first/depth/blend
policy remain unchanged. Changing weights prepares colors but never generates a
new rig. Wireframe remains independent.

Pure copied-data tests cover boundaries, draw spans, stable full coordinates,
invalid-span recovery, stale diagnostics, display metadata, selected skeleton
colors and generation coalescing. These are not physical Metal/GUI/VoiceOver
acceptance. Three-dimensional picking, pose/deformation, broader modeling with
the local core and full Qt/HIG parity remain outstanding. Production pin and
quarantine boundaries are unchanged.
