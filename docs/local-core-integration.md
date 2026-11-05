# Isolated local core integration

For paired local development, run an isolated SwiftPM build against a checked-out `dust3d-core`:

```sh
python3 script/local_core_integration.py --core /absolute/path/to/dust3d-core \
  --build-root /absolute/path/to/disposable-builds build --product Dust3DEditor
```

Use `test --filter TestName` to run a focused test. Supported forwarded arguments are `--product`, `--filter`, `--configuration`, `--enable-code-coverage`, and `--parallel`; path, cache, linker and other overrides are rejected. Each invocation prints and retains its own fresh build directory. Products are in its `build` directory. Remove those directories when finished.

The tool copies tracked and unignored app inputs into that directory, resolves the unchanged pinned manifest, then asks SwiftPM to edit the dependency to the specified core checkout. It verifies SwiftPM's workspace state and package link, protects the exact resolved file bytes, runs the GLB quarantine check, and checks both original trees, copied inputs and identity file for changes. Indexed Git submodules are represented by empty directories; their recorded identities are checked and their contents are not compilation inputs. Tracked or unignored input symlinks in either checkout, including symlinked parent directories, are rejected; their targets cannot otherwise be represented reliably in the captured source identity. The core checkout must also contain no Git-ignored files, because SwiftPM can compile them without recording them in the source digest. Use a dedicated clean core worktree and keep build products and caches outside it. All SwiftPM and compiler caches are isolated. Builds embed the actual app and core revisions, source digests and dirty states; diagnostics expose the additional core fields. A successful build is invalid if any verification fails.

This workflow does not replace the ordinary pinned `make ci` gate or reviewed core and dependency updates. It does not update the production manifest or pin. It requires SwiftPM to resolve the production dependency before switching to the local checkout, so resolution may require network access.

## Reviewed hollow preview experiment

The optional `-Xswiftc -DMOTE3D_EXPERIMENTAL_HOLLOW` flag is the only compiler
flag this helper admits. It enables the hollow inspector and the explicitly
admitted `HollowNativeHistoryTests`; the flag is recorded in the embedded identity
JSON as `experimentalFeatures`. All other compiler/linker/path overrides remain
rejected. Use it only with the reviewed hollow core, currently
`c4607af815d90394ac617c36e764c6150da20f5f`, after running both source guards and
checking that the core checkout is clean, including ignored files.

```sh
MOTE3D_EXPECTED_CORE_REVISION=c4607af815d90394ac617c36e764c6150da20f5f \
DUST3D_BUILD_JOBS=2 python3 script/local_core_integration.py \
  --core /absolute/path/to/core-hollow-endpoint-review \
  --build-root /absolute/path/to/disposable-hollow-builds \
  test --filter 'HollowArchiveTests|HollowHistoryTests|HollowNativeHistoryTests' \
  -Xswiftc -DMOTE3D_EXPERIMENTAL_HOLLOW
```

The native contract uses only one readable two-node tube and its four authored
archive states. Material/import/animation services are blocked, and preview calls
reject any other bytes. It checks cavity generation, exact solid endpoint buffers,
Undo/redo, no-op/invalid edits, save/reopen and embedded core identity. This is not
permission to run quarantined fixtures, fault probes, GLB/material experiments or
live pose evaluation. Inspect admitted source before execution; never reuse old
experimental binaries.

The production pin remains unchanged and its preserved-metadata warning remains
visible. These document commands alone do not establish hollow geometry support in
the standard editor. A dependency update, combined editor acceptance and physical
inspector/keyboard/VoiceOver verification remain separate gates for issue #96.
