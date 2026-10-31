# Goal

Resume the modeling-focused beta on another machine. This is a recovery checkpoint, not a merge or release approval.

# Current status

App repository: `dalbrecht/dust3d-swiftui`; core repository: `dalbrecht/dust3d-core`.
Board: https://github.com/users/dalbrecht/projects/5/views/2
Draft app PRs: #288 export warning accessibility and opt-in source mip copies; #289 gesture safety; #290 isolated local-core build tooling. Recheck GitHub CI and automated reviews before advancing them.

# Completed

- App candidate `5ae3bee4007caea1e9e8543dd1b4065dbcfa85a8` contains integrated beta work and delivery documentation. Validated implementation parent: `fcf46d5a9d8934c6420f2689592dce9c64764c1a`.
- Coordinated exports #185: `c49d6432aa9dd9e2a6513f2c3ff7548cc9589daf`.
- Core mixed-mip acceptance/fixes #59: `3b7f4302bedc50446407965b171a2b15f24a511a`.
- Core indexed OBJ #63: `e9c869cfe4c3acfcf329b034de00f46d89352a97`.
- Core hollow design notes: `ac74a5a9cb9d285c9c62508b5cafcb92b2a5c24f`; separate hollow worktree contains an intentionally failing regression.
- Experimental local native-mip-to-Metal test is preserved as a patch, not adopted into production. It requires the unreviewed local core.

# Validation

Previous exact local gates: gesture f558b4f4: 45 support/1,126 XCTest; tooling 3c23d54c: 60/1,102; coordinated exports c49d6432: 45/1,110; combined fcf46d5a: 60/1,139. Gates include coverage reports, Qt-free linkage and bundle verification. These are prior measured results, not validation of every recovery snapshot. Core positive source-audited tests and focused sanitizers passed as recorded in evidence logs. Experimental native mixed-mip Metal test passed 1/1; solid-color charts do not prove nonzero GPU LOD selection. No new builds/tests are needed merely to archive the source.

# Next steps

1. Fetch checkpoint tags and choose the appropriate task branch from `refs.json`.
2. Recheck draft PR CI/reviews. No merges have been authorized by this transfer request.
3. User explicitly selected indexed UV/source ownership refactoring FIRST for hollow thickness #96. It has not started. Trace corner UV/source ownership through MeshGenerator, Object/MeshState, booleans/quad recovery, UvAtlasBuilder and source atlas; add ADR and incremental regression coverage before implementing hollow geometry.
4. Review core mip/OBJ changes independently before app dependency adoption. Production core pin remains `48b0ce2d6d61cf58731bb0c3e14ef5965a686d68`.

# Risks/blockers

Preserve source quarantine rules for core #67/#69/#83/#84/#95 and app #199. Never run allocation-failure, crash, OS-signal or resource-exhaustion probes, or the historical #83 writer fixture; never reuse pre-containment binaries. Inspect source registration, run the source quarantine guard, build fresh and run only audited targets. Archived source/fixtures are evidence, not execution authorization. Core tests were deliberately not launched by the checkpoint-tag uploads.

Physical window input, held Escape, VoiceOver, older macOS, sandbox/cloud provider acceptance remain outstanding. Hosted input tests are not physical event routing proof. The old machine's existing QA app PID 7135 may have unsaved data: it was left untouched. No caches or compiled apps need transfer; rebuild on the new machine. Machine-local hook paths in the root untracked configuration must be adapted before use.

# Files/context

- `refs.json`: mapping of original local refs to remote immutable checkpoint tags, with exact commits and repository.
- `snapshots/*/metadata.json`: original worktree base/head and untracked-file list.
- `snapshots/*/working-tree.patch`: binary-safe tracked changes against that exact HEAD; some intentionally red/incomplete experiments.
- `snapshots/*/untracked/`: untracked source/configuration saved separately. Do not blindly install machine-specific hooks.
- `evidence/`: source excerpts, experimental patches, exact validation logs and source identity records.
- Candidate `docs/editor-delivery-status.md` records integration evidence; this handoff supersedes its earlier undecided hollow/publishing status.

Recover one dirty worktree: create a branch/worktree at the metadata HEAD, run `git apply --check /path/to/working-tree.patch`, then `git apply /path/to/working-tree.patch`, and copy its saved untracked files into that worktree. Preserve existing edits; do not apply patches across a different base. The root stash is preserved by a checkpoint tag; inspect it before `git stash apply <sha>`.

## Fetch on the new machine

```sh
git clone --branch codex/machine-transfer-20261031 https://github.com/dalbrecht/dust3d-swiftui.git dust3d-apple
git -C dust3d-apple fetch origin 'refs/tags/handoff/20261031/*:refs/tags/handoff/20261031/*'
git clone https://github.com/dalbrecht/dust3d-core.git dust3d-core
git -C dust3d-core fetch origin 'refs/tags/handoff/20261031/*:refs/tags/handoff/20261031/*'
git -C dust3d-core worktree add -b codex/mixed-mip-review ../core-mip-work handoff/20261031/core-recovery/heads/codex/mixed-mip-acceptance
```

The transfer branch includes the combined app candidate plus this archive at `docs/machine-transfer-20261031/`. Use worktrees from task-specific checkpoint tags for independent work. Immutable tags preserve historical local branches without creating dozens of active development branches or starting unreviewed core test matrices. Compiled caches/apps and redundant historical `.bundle` files are not copied into source control.
