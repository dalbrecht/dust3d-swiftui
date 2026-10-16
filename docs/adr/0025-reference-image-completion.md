# ADR 0025: Fit visible reference-image transitions, not empty completions

Accepted 2026-10-16. Tracks #51, a CI blocker found while validating #50.

Hosted CI caught a delayed empty reference-image result resetting the camera after an origin edit. The store reported no pending image work for absent assets, but still scheduled a cache-resolution task whose `forceFit` completion called Fit. Timing made the original origin-drag assertion intermittent. Do not weaken the camera assertion or retry away this product race.

Track every pending reference-image resolution until its request-identity-guarded completion, including absence; show a loading indicator only when the document actually contains a reference asset. Remove a displayed image and fit immediately. An empty completion only finishes cache bookkeeping and must not reset the camera or cancel a new origin draft. A decoded image refits when changed, forced by Load, or newly appearing even on an actor-cache hit. On failure, refit only when a previously displayed image was removed. Existing cancellation, stopped-window and request-identity guards still isolate obsolete completions.

Introduce an internal Sendable `ReferenceImageServing` protocol at the existing ImageIO/actor boundary. Production uses the same `ReferenceImageService`; no new dependency or domain/framework coupling is introduced. Tests inject a controlled actor, holding the empty result until after an origin edit/draft and exercising a cached image restored by Undo while the obsolete absence request remains pending. Both camera failures were reproduced before the fitting fix. Primary document/history operations remain independent of this derived cache.

This preserves existing fitting for actual reference-image changes while removing redundant empty/failure fits. It changes neither archive data nor mesh generation/C++ behavior. The fix is included in #50 because its required CI gate exposed it; the next feature cannot begin until that gate is green.
