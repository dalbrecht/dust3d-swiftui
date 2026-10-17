# ADR 0041: Lossless part deformation foundations

Status: Implemented for review. Tracks #81 and M3 #62.

Expose width and thickness through `PartDeformationProperty`, immutable optional
metadata and separate typed scale/unified commands. Scale bounds are finite
0...2, matching the inherited Qt part setters; reject invalid edits rather than
silently clamping. Nonzero subnormal doubles are rejected because the core parser
reports underflow. Imported literals that Swift rounds to zero despite a nonzero
significand remain unavailable until explicitly replaced; do not preserve them as
semantic zero no-ops. Nonzero values must also remain nonzero and finite after conversion to the
engine Float. Explicit zero and the smallest nonzero Float remain valid.
Defaults are one and unified false. Unified deformation uses
the maximum node radius for nondefault scale directions; it does not make width
and thickness equal or rewrite node radii.

Absent scales read as one. Empty, nonfinite, out-of-range or unsupported source
scale values remain nil and preserved until explicitly replaced. Explicit empty
scale metadata differs between the inherited Qt numeric parser (which rejects
empty text) and core generation (which uses one), so do not silently resolve it. Known unified boolean spellings follow the inherited
parser; unsupported spellings remain nil. Each command changes only its chosen
attribute, preserving other scales/flags, per-node deformation, graph and assets.

Write every explicit nondefault numeric value, including 0.995 and 1.005. Qt's
writer omits scales less than 0.01 away from one; reproducing that omission would
lose valid fine edits. Exact default one removes the attribute on an actual edit.
A semantic no-op preserves original spellings, bytes and redo. Explicit part
metadata edits preserve part visibility, disabling and locks, as inherited part
setters do; node transforms remain constrained separately.

The serialized editor controller applies edits in one history step and regenerates
without changing camera/selection. Invalid input publishes no document or preview
revision. This is a document/controller PR, with no native inspector controls.
Native deformation controls, rendered interaction, Qt differential fixtures and
VoiceOver acceptance remain follow-up work. No new dependency or C ABI is needed.
