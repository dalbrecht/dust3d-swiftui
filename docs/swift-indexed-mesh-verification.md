# Swift indexed mesh verification

Tracking: Apple issue #104; ADR 0052. Core PR #18 is merged at exact revision
`50c41f131b6bfdf03bcda1ce0dc060de3b093169`.

## Contracts

- Immutable Sendable arrays own all vertices and UInt32 triangle indices.
- Source counts and compatibility warnings are copied before native destruction.
- Expanded native storage is destroyed before Swift indexed-buffer copies.
- Zero payload budget uses the core default; negative budgets reject before C.
  The budget excludes generation, deduplication workspace and Swift copies.
- Optional results represent only successful no-geometry; malformed input,
  insufficient budgets and unrepresentable float geometry remain typed failures.

## Evidence

Tests were first run against the absent APIs and failed to compile. The focused
six-test suite then passed. Capsule, Sword and RoundedCrossing compare semantic
bounds, triangle/source counts, warnings and finite unit-normal attributes against
expanded output without depending on independent generation order.

An independently serialized synthetic diamond has four unique vertices, two
triangles, area 0.32, planar normals and known RGBA. It also exercises copied
nonempty warnings. Further tests cover negative/insufficient/sufficient budgets,
successful empty versus genuine precision failure, retained arrays after unrelated
loads, and concurrent Sendable results. The core separately tests per-attribute
seams, reconstruction and native ownership under sanitizers.

Full `make ci` passes: 458 tests, formatting, builds, coverage, Qt-link checks
and isolated bundle-rebuild regression. Swift mesh coverage is 130/132 lines
(98.48%); document 2812/2896, model 1462/1468, pure editor state 529/529,
undo 97/97 and orbit camera 33/33. No UI change is included. Indexed
GPU rendering, large-model peak-memory profiling, source IDs and differential Qt
acceptance are still pending. Existing inherited C++ coverage is not claimed to
meet 100%.
