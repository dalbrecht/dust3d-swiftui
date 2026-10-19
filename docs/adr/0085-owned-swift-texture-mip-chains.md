# ADR 0085: Owned Swift texture mip chains

Status: Local implementation under #175; public review pending. Related: M4 #143,
core #59 and its portable/native mip ownership stages.

## Context and decision

Image dimensions cannot establish that mip levels were retained, nor prove their
chart safety. Add TextureMipChain with immutable Swift-owned RGBA8 levels and a
producer-supplied sampling cap constrained by actual level availability. Validate
1...14 levels, 1...8192 image dimensions, packed complete byte spans, exact halving
with a floor of one and no repeated terminal level. Partial/rectangular chains
are valid; missing levels are never synthesized. No filtering occurs in Swift.

TextureMipChainCopy receives synchronous borrowed views while the caller retains
the native owner. Validate counts before any accessor call and validate each view
before reading its pointer. Copy Data bytes, charge image-array capacities and
all pixels against one cumulative Swift quota, and deduct every copied pixel
span from the remaining native aggregate. Original accessor failures propagate;
cancellation before/after borrowing and before publication never publishes a
partial chain. Temporary workspace and allocator overhead are not RSS-capped.

Reuse the checked image-copy primitive in the production base source-bake path.
That path copied only base pixels, yet its old validation accepted positive LOD
from dimensions alone. A failing regression now proves those caps reject even
when the base dimensions could support hypothetical additional levels.

## Verification and remaining adoption

Test-first contracts cover odd/rectangular/partial dimensions, missing/duplicate
levels, malformed spans, unavailable LOD, ownership after caller storage mutation,
exact/one-byte-short copy quotas, original accessor errors and cancellation.
Real source-bake/archive tests pass against the unchanged exact reviewed core pin.
An earlier local checkpoint `make ci` passed 863 XCTest cases and 31 build-support tests,
coverage checks, Qt-link checks and bundle-rebuild checks. At that checkpoint TextureMipChain covered
38/38 lines, 27/27 regions and 6/6 functions; TextureMipChainCopy covered 41/41
lines, 28/28 regions and 3/3 functions. SourceBakedCopy measured
174/175 lines (99.43%), 108/114 regions (94.74%) and 17/17 functions. This does
not claim full inherited-core or whole-editor coverage. Current integration results
are recorded in the delivery PR; historical counts are not current measurements.

This stage does not call unreviewed native APIs, expose enabled mipmaps in apps,
or change Package.swift/Package.resolved. After the core change is reviewed and
pinned, bind actual count/level accessors and retain chains in source results;
then upload every level in Metal and verify actual trilinear sampling. Procedural
packing/large-model acceptance and textured export/re-import remain required.
No new dependencies or user-visible UI controls are introduced.
