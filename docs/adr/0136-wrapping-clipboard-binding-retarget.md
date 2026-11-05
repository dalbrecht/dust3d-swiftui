# ADR 0136: Retarget copied wrapping body bindings

Status: accepted for local delivery; integrated pinned full gate passed.

## Context

Qt retains group `wrapBindTo` metadata and remaps it through the paste identity map when its target is copied (application/sources/document.cc:2571–2584). Native copy preserves the attribute and prunes the component hierarchy to selected nodes, but paste previously remapped component identities and part links without retargeting this binding. A copied garment could therefore continue referencing the original body instead of its copied body.

## Decision

Retarget `wrapBindTo` only on semantic component elements during the existing atomic paste. Index the already validated original-to-fresh identity map once and substitute each retained binding once. Match the existing brace-alias identity policy: UUID-shaped braced and unbraced spellings resolve to the same original identity, while case remains significant. This follows the inherited Uuid constructor, which removes braces without folding case. Arbitrary non-UUID text stays exact.

When the target has been pruned or is absent from the fragment, retain its exact binding text, even if the destination has an existing object with that identity. This preserves Qt's external-reference behavior; paste does not silently substitute the garment, another target, or a newly generated identity. Do not expand copied selection to import a body dependency. Preserve unrelated wrapping parameters, opaque content and assets. Existing collision preflight, history, selection, offset and paste-partition policies remain unchanged.

This is a clipboard repair, not binding authoring or validation. It does not establish cycle/ancestor safety, animation/export support, or new native geometry behavior. Missing imported references remain preservable.

## Verification

Test-first failure demonstrated unchanged `body` instead of `new-body` after same-document/cross-document paste and reopen. Pure document tests cover both copied groups, nested pruning, external/missing/opaque targets, brace aliases, case distinction, simultaneous replacement, assets and exact Undo/Redo. Actor tests exercise native and Qt payload routes, fresh graph selection and independent sessions. Store tests use the existing independently authored wrapping fixture with an injected preview stub, retaining window isolation and exact history without a new kernel fixture. A focused clipboard regression run passed 36 tests. Full integrated validation follows review and beta11 integration; no dependency pin or quarantines change.

The final integrated make ci completed exit 0: 60 BuildSupport and 1,370 XCTest tests, configured coverage (903/903 EditorState lines), Qt-free products and isolated bundle rebuild/signature checks. Physical application and VoiceOver acceptance remain outstanding.
