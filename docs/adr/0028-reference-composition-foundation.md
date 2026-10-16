# ADR 0028: Reference composition layout and raster boundary

Status: Accepted

## Decision

Implement reference composition in two reviewed stages: pure crop/layout plus raster correctness first, then transient SwiftUI drafts and an atomic document commit. Keep #56 open until the full workflow and native acceptance are implemented. The foundation adds no menu or automatic archive mutation.

`ReferencePixelSize` bounds source dimensions to 8192 per side and 16 Mi pixels. `ReferenceImageCrop` uses integer, top-left, half-open pixel coordinates. Numeric crops must be nonempty and fully contained; invalid input fails rather than silently changing user values. Pointer endpoints normalize and clamp before subtraction, avoiding integer overflow even at Int.min/Int.max. Horizontal mirroring transforms the crop coordinates when mirroring the whole source. Raster mirroring instead flips the selected crop; the UI stage must pair these semantics deliberately rather than conflate them.

`ReferenceCompositionLayout` is pure and imports only the document value types. Each profile scales to height 512; widths round to the nearest pixel. Front is centered in the left half, Side in the right, on a white canvas at least 1024 pixels wide. Twice the maximum scaled profile width dominates the combined-width constraint, so the canvas width is always even. Integer centering preserves the inherited half-pixel center offsets for odd profile widths. Derived origins use these actual centers, Y 0.5 and the empty half's center when a profile is absent.

The inherited `TurnaroundPreviewWorker` and `computeResultOrigins` are the source comparison. Native deliberately retains a one-pixel width for an extremely thin crop that would round to zero, and rejects projected output wider than 8192 instead of unbounded allocation. Sources are orientation-normalized by the existing import boundary. Existing composed PNGs do not recover their original two sources or crop metadata.

`ReferenceCompositionRaster` validates source/image size agreement, allocates a bounded sRGB RGBA canvas, composites cropped profiles over white, and uses the shared bounded PNG encoder. Call it off the main actor; the following UI/service stage will own async orchestration and cancellation. Cancellation is checked before layout, per profile and around encoding. CoreGraphics interpolation is not claimed pixel-identical to Qt SmoothTransformation; synthetic solid regions test geometry/orientation, and differential resampling remains acceptance work.

## Follow-up

The next stage must provide per-window transient sources/crops, independent imports, side mirror and source swap, preview, explicit Apply/Cancel and stale-document guards. Apply image and intended origin changes as one existing document transaction, respecting native locks. Failure/Cancel must retain exact archive/history. Numeric controls and accessible pointer crop gestures require their own state/coordinate tests and native QA. No C++ adapter, dependency, core pin or CI configuration changes are needed.
