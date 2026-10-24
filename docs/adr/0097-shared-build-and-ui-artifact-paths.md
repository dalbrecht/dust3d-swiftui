# ADR 0097: Share cache and UI artifact paths

Status: Local full gate passed; automated review pending. Refs #147.

## Decision

Default compiler-cache identity follows the canonical Git common directory,
rather than the active checkout path. Linked worktrees therefore share a build
root. Explicit DUST3D_BUILD_ROOT retains priority and permits sharing one existing
root across the Apple and core repositories. Unrelated Git repositories remain
separate by default. If Git metadata is unavailable, including an older Git that
cannot resolve an absolute common directory, use the canonical source path as the
stable fallback. Directory discovery does not create cache folders.

Default DUST3D_UI_QA_OUTPUT_DIR to build-root/ui-qa, preserving an explicit override.
Existing render helpers already create this destination and use stable capture
names; repeated gates stop producing a new UUID-named capture directory for each
helper call. These outputs are current inspection artifacts, not committed visual
baselines. Preserve needed review captures before another run overwrites them.
No old evidence, compiler cache or live application bundle is removed or migrated.

One build at a time must use the shared root. Existing source identity checks,
source/core pin validation and isolated packaging checks remain required. This
change introduces no dependency or CI configuration and does not change the
production core pin or any quarantine.

## Evidence

Six disposable-repository tests initially failed four assertions covering cache
sharing, aliases and missing artifact defaults. They now pass for linked worktrees,
explicit build/artifact overrides, unrelated repositories, unavailable metadata
and canonical source aliases. They do not compile product code or create caches.
Full `make ci` at 2b789900 passed 42 support checks and 913 XCTest cases,
zero failures (119.327 seconds), formatting, coverage, Qt-link and isolated
packaging/provider checks. Captures used the existing shared root and its ui-qa
folder (25 MB), not another build cache. The final follow-up changes documentation
only. No UI appearance,
performance-budget or milestone completion is established by this infrastructure
change. No live QA process is contacted.
