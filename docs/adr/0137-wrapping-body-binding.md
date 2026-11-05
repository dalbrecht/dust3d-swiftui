# ADR 0137: Wrapping body-weight source authoring

- Status: Proposed
- Scope: Native document, actor, inspector, and source-audited SDK acceptance

## Decision

Expose a Skin/Cloth group's `wrapBindTo` as a separate “Weights From” picker. Own Children removes the attribute; a supported group choice stores its exact identifier. The field-local command preserves all other wrapping attributes, unknown parameters, assets, and imported references until an explicit replacement. Missing and empty values are distinct stored values but both mean Own Children for authoring; choosing that semantic value does not normalize an imported empty spelling or consume redo.

Candidate planning excludes the owner and its descendants, permits ancestors, and never follows binding references. This follows the Qt chooser (`component_property_widget.cc:778–798`) and avoids inventing a binding-cycle prohibition. Native authoring currently accepts supported unlinked groups only: Qt's part-link-only check also admits unknown link kinds, whose semantics remain unsupported here. Such imported references remain lossless, including self, descendant, missing, linked, opaque, and byte-distinct Unicode values. A retained ineligible reference can still affect the core; the inspector does not label it ignored. Picker identity equality and hashing use exact UTF-8 bytes.

The actor command captures the originating document, document revision, selection and constraint epochs plus active group. It stages the field edit on a local state copy and checks cancellation before publication. A changed binding advances geometry/source-hint and material input identities, produces one undo entry, and retains component selection. Semantic no-ops preserve archive bytes, preview identity and redo. Retained view callbacks cannot retarget another selected group.

## Native meaning and validation boundary

Pinned production core `48b0ce2` collects target weight samples through hierarchy traversal, not binding edges (`mesh_generator.cc:1865–1924`). Missing or self targets skip target binding. When an existing target supplies no usable samples, guide weights remain; its surface may still influence fold placement (`2114–2213`). This is not a promise that every unsupported authoring choice is inactive, nor a claim that binding metadata establishes animated garment export.

The public Swift source catalog describes original identities. Legitimate interpolated donor nodes are created after that catalog and can remain unresolved in copied hints. Swift acceptance must report those entries honestly. A separately hash-admitted, source-audited test-only C++ observer on exact production48b checks each influence against the actual generated snapshot, including interpolated BODY nodes, without extending the production API or changing core/pin.

The bounded collision-free fixture family has ordinary body and garment guide chains. Direct fresh production48b observation yields BODY ownership for all 247 bound influences, including 139 virtual-node influences, and 10,383 serialized fold bytes. Own Children, a returned Own Children state, and a sampleless empty target retain all 137 GUIDE influences. Their zero fold bytes are valid: an initial unconditional fold assertion was an oracle overreach and its failure log remains preserved. Nonempty folds remain mandatory for the bound case.

Real Store acceptance is separately required: invoke the actual captured authoring action, inspect resolved public source hints while retaining unresolved entries, require a changed nonflat baked normal map, compare an independent fresh bake/reopen of identical bytes, and verify undo/assets. The separately reviewed real Store test passes on the unchanged production pin: 65,536 valid opaque normal texels, 803 perturbed texels and 302 distinct valid directions; a new-window fresh bake matches exactly, and Undo restores the original guide-owned state. Direct companion success alone is not feature completion. Native fixture variants and caller source are reviewed and hash-admitted before execution. No cyclic native probes, parameter sweeps, core adoption, or dependency-pin changes are part of this decision.

## Verification

Pure focused tests cover lossless imported values, exact Unicode picker identities, ancestor and descendant eligibility, field locality, no-op/redo semantics, actor/window staleness, constraints away-and-back, cancellation, Store routing, and stale child-view admission. Hosted light/dark picker rendering uses stubs for every native boundary. The first reviewed native Store acceptance passes (one anchored test). Final combined release gates must be recorded before accepting this ADR. Physical pointer/VoiceOver acceptance remains separate.
