# ADR 0045: Procedural part target roles

Status: Accepted for the native editor prototype.

Expose Model, CutFace, StitchingLine and StitchingLoop using their inherited
archive spellings. Missing/empty targets read as Model, while unknown values
and ImportedModel remain unsupported source metadata until explicit replacement.
Imported-model creation belongs to M4's bounded embedded-model pipeline.

Use a typed lossless command and the existing session/store mutation path.
Changing roles preserves source nodes, flags, links, opaque metadata and assets.
Part locks constrain node edits rather than blocking metadata restoration.
Semantic no-ops preserve exact bytes and redo; Model only removes an attribute
when a real semantic change occurs. The native picker offers supported roles
and a disabled unsupported placeholder only when needed.

A CutFace part supplies cross-section data rather than ordinary joined geometry.
Profile-only documents therefore clear the joined preview intentionally, while
keeping graph overlays and selection editable. Disabled parts remain excluded.
Stitching inputs stay eligible for generation, with component configuration and
subsequent stitching parameter controls determining surface output. Unknown
roles retain core diagnostics rather than being silently suppressed.

The actual inspector and role states use the hidden-window rendering QA path
from ADR 0043. Static output does not establish keyboard, pointer, VoiceOver or
GPU acceptance. Full stitching and Qt differential parity remain separate work.
