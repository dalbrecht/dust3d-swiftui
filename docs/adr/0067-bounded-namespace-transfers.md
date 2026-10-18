# ADR 0067: Bound namespace materialization across a paste

Status: accepted decision. Tracks Apple #67.

## Decision

Use one `DocumentXML.NamespaceBudget` for every graph and archive-header transfer
in a `.pasteNodes` command. The quota is 100,000 newly installed bindings and
16 MiB of UTF-8 prefix/URI payload plus a logical 16-byte charge per binding.
Check the complete binding set against the remaining quota before allocating its
XML namespace nodes. Both inherited-binding preservation and explicit default
namespace replacement use the checked installer. Matching existing-asset metadata
consumes the same operation budget when it materializes inherited bindings.

Reuse the same policy for component structural edits, replacing its private copy
of the budget. Existing source XML and archive input limits still apply. This
quota bounds additional namespace materialization, not parser/workspace/driver
memory, native object overhead or total process RSS. Computing an inherited-scope
projection still happens on already bounded parsed input.

## Compatibility and failure behavior

Graph objects continue to adopt the destination canvas namespace. Opaque child
extensions retain source default and prefix bindings, including QName-valued
attributes. Asset header metadata retains its original prefix meanings even when
the destination header uses the same prefix for a different URI. No namespace
renaming, asset re-encoding, new dependency or archive schema change is introduced.

Quota failures throw `DocumentError.limitExceeded`. All mutation occurs on
operation-owned XML copies; a failed command publishes neither a partial document
nor an undo entry. Per-operation quotas deliberately reject some formerly accepted
large expansions even when the small source archive itself is within input limits.
Semantic no-ops and normal transfers retain their existing exact-save/history
behavior.

## Evidence

Three public command regression tests first failed: excessive clipboard expansion
was published, and asset/header growth reached a later archive error instead of a
typed quota error. A subsequent failing test exposed direct default-namespace
allocation outside the first budget implementation. The shared installer fixes
both paths. A mixed graph/asset fixture confirms that separate individually
permitted phases cannot reset the cumulative budget.

A normal transfer into conflicting destination scopes verifies source default
namespace meaning for opaque children, prefixed attribute namespaces and QName
text, binary asset bytes, unchanged source archives and exact Undo/Redo. Existing
clipboard and structural tests remain green. Seven namespace regressions pass alongside existing clipboard and structural
checks. Shared-asset comparison work consumes the quota even when no new asset
is inserted. The full local gate passes 634 tests, formatting/build, measured coverage
thresholds, Qt-free linkage and signed bundle rebuild checks. Automated review
and all remote CI checks remain required before merge. The tests use bounded
amplification fixtures rather than exhausting machine memory.
