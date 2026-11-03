# Isolated local core integration

For paired local development, run an isolated SwiftPM build against a checked-out `dust3d-core`:

```sh
python3 script/local_core_integration.py --core /absolute/path/to/dust3d-core \
  --build-root /absolute/path/to/disposable-builds build --product Dust3DEditor
```

Use `test --filter TestName` to run a focused test. Supported forwarded arguments are `--product`, `--filter`, `--configuration`, `--enable-code-coverage`, and `--parallel`; path, cache, linker and other overrides are rejected. Each invocation prints and retains its own fresh build directory. Products are in its `build` directory. Remove those directories when finished.

The tool copies tracked and unignored app inputs into that directory, resolves the unchanged pinned manifest, then asks SwiftPM to edit the dependency to the specified core checkout. It verifies SwiftPM's workspace state and package link, protects the exact resolved file bytes, runs the GLB quarantine check, and checks both original trees, copied inputs and identity file for changes. Indexed Git submodules are represented by empty directories; their recorded identities are checked and their contents are not compilation inputs. Tracked or unignored input symlinks in either checkout, including symlinked parent directories, are rejected; their targets cannot otherwise be represented reliably in the captured source identity. The core checkout must also contain no Git-ignored files, because SwiftPM can compile them without recording them in the source digest. Use a dedicated clean core worktree and keep build products and caches outside it. All SwiftPM and compiler caches are isolated. Builds embed the actual app and core revisions, source digests and dirty states; diagnostics expose the additional core fields. A successful build is invalid if any verification fails.

This workflow does not replace the ordinary pinned `make ci` gate or reviewed core and dependency updates. It does not update the production manifest or pin. It requires SwiftPM to resolve the production dependency before switching to the local checkout, so resolution may require network access.
