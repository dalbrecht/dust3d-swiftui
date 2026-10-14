# Public repository setup

Configured October 14, 2026:

| Repository | Role | License |
| --- | --- | --- |
| [dalbrecht/dust3d-swiftui](https://github.com/dalbrecht/dust3d-swiftui) | Existing GitHub fork; standalone viewer and future SwiftUI editor | MIT project code; inherited dependency notices retained |
| [dalbrecht/dust3d-core](https://github.com/dalbrecht/dust3d-core) | History-preserving downstream core with portable build/tests | MIT project code; inherited dependency notices retained |

Upstream is [huxingyi/dust3d](https://github.com/huxingyi/dust3d). Initial tracking
revision is `3fbcaa7a3e8792d1c2ca31ca2ade442dcd21b222`. The core's `upstream-sync`
branch retains untouched upstream commits; maintained `master` adds the native
adapter, CMake build, CTest contracts, standards and core CI. This is not a decision
to stop integrating upstream. No rewritten history, private repository, relicensing
of third-party code or unattended sync task is involved.

The core's `docs/upstream-maintenance.md` documents fetch, fast-forward tracking and
reviewed merge procedures. Both repositories pin the same coding-standards revision.
The existing Apple fork remains suitable for proposing focused upstream fixes.

The standalone viewer PR remains independent and still builds its in-tree engine.
A dedicated dependency-migration PR will replace that copy with a pinned core
dependency after document/API compatibility gates pass. The core setup is source
infrastructure, not a promise of a stable binary ABI or complete editor features.

See the [updated implementation and testing plan](editor-port-plan.md). Initial
headless tests cover a pure-C ABI consumer, null handles, rejected archives, early
input limits, two real generated models and mesh-buffer ownership. Full algorithm
coverage, fuzzing, document encoding and differential fixtures are scheduled work.
