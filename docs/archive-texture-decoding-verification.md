# Retained archive color-image decoding verification

Scope: Apple issue #125, ADR 0062. No UI or full M3/M4 parity claim.

## Targeted evidence

Failing-first compilations recorded the absent texture-reference, PNG-decoder and
archive-baker APIs before implementation. Four document tests pass for opaque,
case-sensitive and all-zero identities, brace aliases, empty references,
missing/ambiguous/wrong-kind assets, byte-exact preservation and canonical-equivalent
Unicode keys that remain distinct under the engine's exact UTF-8 identity rule.

Four decoder tests pass with independent PNG scanline fixtures for 20 sample
families (grayscale, RGB, indexed, alpha, 1/2/4/8/16-bit, transparency keys),
encoded EXIF orientation, hidden RGB below zero alpha, low alpha, malformed
container spans, invalid limits and encoded/decoded quota rejection. Sixteen-bit
expected bytes use the reference Qt rounding rule. Fixtures are codec inputs,
not environment-specific rendered snapshot baselines.

Four service tests pass with the actual pinned native baker: expected baked
red/blue RGBA samples, retained opaque bytes, per-image/aggregate encoded quotas,
aggregate decoded quotas across distinct images, exact-budget success, original
asset-specific decoder cause and cancellation before archive loading.

## Full gate

`make ci` passes: 580 tests, zero failures (85.444 s), full native build,
strict formatting, coverage, Qt-free sources/both app linkages and isolated bundle
rebuild regression. Swift mesh library: 1413/1432 lines (98.67%); document:
2984/3072 (97.14%); editor model: 1490/1496 (99.60%). Pure state 529/529,
undo 97/97 and orbit camera 33/33. This does not assert inherited-core or GPU
coverage.

A separate local Qt 6.12 QImage reference executable decoded the same 20
sample-family fixtures plus the orientation/low-alpha fixture and converted to
RGBA8888. All 21 outputs match the native decoder's expected samples. The broader
comparison exposed keyed transparent grayscale behavior: Qt zeros RGB at depths
2/4/8 while retaining it at 1/16 and for explicit alpha. Failing-first regression
fixtures drove that narrow compatibility conversion. The reference executable
remains outside native targets. This is sample-level differential evidence, not
full texture/render/color-management parity.

The full gate above includes the final opaque-key equality and grayscale-depth regressions.

Automated review and all remote CI checks remain required before merging.

## Explicit limits

Payload quotas exclude retained archive copies, ImageIO samples/workspace, native
workspace and baked Swift output. Cancellation is cooperative; platform decoding
and inherited geometry cannot be forcibly interrupted. The default apps do not
yet schedule/use textured bakes. No GPU, PBR, AO, transparent ordering, texture
import UI, textured export or broad Qt color-management parity was verified by
this backend change. Native UI acceptance remains in the wider editor plan.
