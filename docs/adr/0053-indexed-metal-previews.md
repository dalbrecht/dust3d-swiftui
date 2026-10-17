# ADR 0053: Indexed Metal previews with expanded compatibility

Status: accepted

## Context

ADR 0052 exposes copied indexed geometry. The native apps still uploaded expanded
triangles, repeating GPU vertex attributes for shared position/normal/color values.

## Decision

Use `IndexedMesh` for viewer loads and editor preview state. Add indexed loading
to the existing serial file service, sharing bounded file reads with its expanded
method. Preserve optional no-geometry and request identity behavior in the editor.

Keep the public expanded viewport initializer and SDK loader compatible. An
internal tagged input selects expanded or indexed drawing. Pure `RenderGeometry`
validates triangle shape, index ranges and finite attributes/bounds, and prepares
the existing normalized float4 position/normal/color layout. Metal uploads UInt32
indices without changing triangle order or shader vertex indexing.

Extract production draw encoding from drawable acquisition so tests can render
the same pipeline, depth state, uniforms and wireframe mode into offscreen targets.
No window activation, synthetic events, new app identifier, dependency or shader
format change is required.

## Consequences

Native app GPU vertex payloads shrink where full vertex attributes are shared;
indices add four bytes per expanded triangle corner. This does not promise lower
memory for every seam-heavy model. The core still generates expanded input before
deduplication. CPU normalization and GPU upload remain on the main actor as before;
performance scheduling, caches and peak-memory profiling require later work.

Offscreen device-relative comparison verifies rendering without committing pixel
baselines. Missing devices explicitly skip the GPU test. Native interaction,
VoiceOver and broad Qt differential acceptance remain separate evidence gaps.
