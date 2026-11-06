# ADR 0153: Opt-in owned source mip copying

Status: Implemented; full gate tracked separately

## Decision

Reconcile the SDK portion of PR288 onto the current candidate. The production
core already exports owned source mip loading and borrowed level accessors.
Expose maximumMipLevels on SourceMeshBakeOptions: zero retains the existing
base-only entry point;1...14 requests isolated levels including level zero.
Input validation runs before native conversion. No core revision change.

The synchronous loader retains decoded inputs until the native call completes,
then copies geometry, metadata and all returned material-role chains before
releasing the owner. Existing TextureMipChainCopy validates count, dimensions,
LOD and native/copy budgets; level zero must match the base accessor pointer,
dimensions, stride and byte count. Required maps cannot silently disappear.
Cancellation and original accessor failures propagate without a partial result.

Keep the app preview policy unchanged. API availability does not establish full
mixed-chart ownership, imported-material, GPU or textured-export acceptance.
The independent warning identity fix from PR288 is already present in the editor.
No native algorithm, dependency, writer, quarantine or production pin changes.

TDD restored the original two opt-in tests before implementation, reproducing
missing maximumMipLevels API errors. The unchanged pinned Capsule and imported
surface fixtures then pass ownership, copied-budget and policy assertions;
shared mip-chain tests cover malformed views and preserved accessor failures.
These are bounded existing SDK contracts, not allocation failure injection or
process resource-exhaustion probes. Full local and current-head remote gates
remain mandatory before publication/integration.
