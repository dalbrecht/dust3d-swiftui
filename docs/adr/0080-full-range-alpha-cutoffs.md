# ADR 0080: Preserve full-range alpha cutoffs

Status: Accepted

## Context

The glTF material schema allows every finite nonnegative alpha cutoff, without
an upper bound. Restricting source metadata to one rejects valid archives.
Converting a Double cutoff directly to Float can round downward and admit a
fragment that the original comparison would reject. GPU subnormal flushing can
also incorrectly admit zero alpha for a positive cutoff. Tracked in #169.

## Decision

Pin reviewed core `41af7d4c1b67dd037e02858e3ef0fdb96a84aebb`, which preserves
full-range cutoff metadata in the reader and source baker. Validate finite
nonnegative values at Swift copy and rendering boundaries. Keep original Double
policy metadata unchanged. Encode a shared Float threshold rounded upward, or
two for cutoffs above one, and a separate positive-cutoff zero-exclusion flag.
Before interpolation, decode MASK vertex alpha through integer Float bits and
scale by 2^24 so positive subnormals and their rounding midpoint remain normal,
while keeping headroom for perspective interpolation. Clamp finite baked vertex
alpha to [0,1] using its ordered bits before scaling, preserving the existing
unmapped color contract without flushing subnormals. Scale material/texture
factors and thresholds the same way, with exponent-separated multiplication to
avoid overflow and underflow. Restore Float subnormal rounding in the scaled
domain after interpolation and each alpha multiplication. Both imported and
source-baked shaders use this comparison for MASK only. Reuse
existing uniform storage and prepare policy parameters before drawing.

## Consequences and verification

This preserves the original Double comparison against available Float alpha
samples; it does not provide Double material math or remove RGBA8 bake
quantization. CPU tests compare independently against Double expressions,
including representable boundaries and simulated threshold flushing. Native GPU
tests cover downward-rounding boundaries, zero, values above one, and ignored
cutoffs in OPAQUE/BLEND. Review regression tests reproduce six native GPU failures
for positive subnormal material/vertex/unmapped-baked alpha, then verify acceptance
at the authored cutoff and rejection just above it. Combined factors cover
round-to-zero and round-up/ties at the subnormal boundary. A second native
regression reproduces three failures before the bitwise clamp, covering alpha2
with cutoff1.5, negative values, signed zero and the largest finite Float. Texture sampling still
uses the samples available from the texture unit; this does not recover precision
already lost by texture filtering/quantization. Archive tests retain exact metadata and unchanged bytes.

Reference: [Khronos material schema](https://raw.githubusercontent.com/KhronosGroup/glTF/main/specification/2.0/schema/material.schema.json).
