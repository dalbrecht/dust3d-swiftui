# Swift generation session verification

Apple issue #108; ADR 0054. This stage pins reviewed core PR #24 at
d691a7feb1718874b3cef0d9c843af961a252b42. Both apps retain their existing
stateless preview behavior; editor adoption follows separately.

The initial focused suite failed because MeshGenerationSession did not exist.
All ten implemented contracts pass against the real core: cold rebuilding and
actual reuse through radius edits/restores; bounded retention and cache-only fallback; invalid budgets and
typed causes; copied buffer lifetime after reset, later loads and destruction;
primary-failure reset/recovery; pre-cancellation; successful empty results;
concurrent shared/independent actors; explicit unknown native outcomes.

Full make ci passes: 478 tests, two explicit Metal-device skips and no failures.
Formatting, warnings-as-errors build, coverage, both Qt-free app linkages and
bundle rebuild/archive isolation checks pass. The skips are the existing
indexed/expanded production Metal comparison and later-revision Metal viewport
recovery test, because this environment exposes no Metal device. No renderer or
view implementation changes here; no GPU pass is claimed for this run.
No app was launched and no human interaction was requested.

Swift mesh SDK coverage is 268/273 lines (98.17%), including the new session
123/126 lines (97.62%). The three residual session lines translate unexpected
native create/stats/reset failures at the thin ownership boundary. No production
failure hooks are added. Document library: 2812/2896; editor model: 1462/1468;
pure editor state: 529/529; undo: 97/97; orbit camera: 33/33. These figures do not
measure inherited C++ coverage.

Opaque handles remain inside synchronous system-lock regions, including actor
destruction, with no unchecked Sendable declaration or newer deployment baseline.
The core adds process-wide serialization. Expanded storage is released after
native indexed conversion, before Swift copying; indexed owners are released
after copying. The exact reviewed dependency and lock file are updated together.

Cancellation is cooperative and cannot interrupt in-progress C++ work. This
suite deterministically covers pre-cancellation; mid-generation cancellation
timing is not a deterministic regression assertion. Post-generation cancellation
checks remain explicit. Cache/output budgets exclude workspace, allocator
overhead and RSS; they are not a hard process-memory ceiling.

Core cached-versus-fresh modifier/asset/failure and allocator-injection contracts
are recorded in the core repository. Editor background encoding/coalescing,
per-document cache lifecycle and diagnostic presentation follow separately.
Source provenance, Qt differential acceptance and controlled performance/resource
budgets remain pending. This does not complete M3 or editor feature parity.
