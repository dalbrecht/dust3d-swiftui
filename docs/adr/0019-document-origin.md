# ADR 0019: Lossless document-origin commands

Accepted 2026-10-15. Tracks #39, the archive foundation for M2 origin tools.

Represent an available origin with the existing immutable `NodePosition`. `Dust3DDocument.origin()` reads the three inherited canvas attributes `originX`, `originY`, `originZ`, returning nil when any is missing, nonnumeric, nonfinite or outside ±1,000,000. This is an explicit supported-value query, not archive migration: unsupported original spellings remain untouched on ordinary open/save. Zero and negative coordinates are valid stored origin values. Do not silently perform Qt's auto-settlement on read.

`.setOrigin(position)` validates all three coordinates before mutation and throws `invalidOrigin` atomically on invalid input. Update existing attributes in place, preserving their order; add missing known attributes only on explicit edit. Do not move nodes, rename components, change part settings or alter opaque assets. Semantic no-ops return the original archive. Existing history groups edits atomically, and model-only net-zero comparison normalizes finite bounded origin-number spellings so returning to the original origin restores exact original bytes and redo.

The pinned core interprets mesh coordinates as `(nodeX-originX, originY-nodeY, originZ-nodeZ)`. An origin edit therefore affects generated placement even though document-node coordinates do not change; native UI must regenerate the preview. Tests compare semantic mesh bounds with tolerance rather than incidental vertex order. The reader's supported bound matches existing node-coordinate limits; it does not certify arbitrary inherited engine resource behavior.

This PR exposes no origin editing UI or global alignment. Native controls, interaction-lock routing, visual markers and any explicit settlement policy belong in the follow-up stage. No C++/core dependency change is required.
