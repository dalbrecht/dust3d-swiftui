# Temporary app icons

The editor has a teal cube marked **E**; the viewer has a blue cube marked **V**.
These original geometric placeholders identify the local apps in the Dock and Finder
until final artwork is designed. The `.icns` files are app resources, not snapshot
baselines. They use the repository's MIT license.

`script/build_and_run.sh` copies the appropriate icon into each bundle and declares
`CFBundleIconFile` before ad-hoc signing. After verification, it refreshes the app
directory modification time so Launch Services can recognize rebuilt metadata at
the same path. Rebuild through that script to see the icon. This does not reset
services or change document associations.

Run `./script/check_app_bundle_rebuild.sh` to rebuild isolated temporary Editor and
Viewer bundles and verify current directory timestamps and strict signatures.
The canonical `make ci` gate includes this check. Both app and ZIP outputs are
isolated; the test verifies existing default archives stay byte-identical with
unchanged modification times. Local packaging can override the ZIP directory with
`DUST3D_ARCHIVE_OUTPUT_DIR`; it defaults to `dist/`.
See Apple's [application registration guidance](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/LaunchServicesConcepts/LSCConcepts/LSCConcepts.html).

Regenerate with macOS AppKit and the built-in `iconutil` (no new dependencies):

```sh
icon_work_dir="$(mktemp -d)"
xcrun swift -module-cache-path "$icon_work_dir/modules" script/generate_app_icons.swift "$icon_work_dir"
iconutil -c icns "$icon_work_dir/Dust3DEditor.iconset" -o assets/app-icons/Dust3DEditor.icns
iconutil -c icns "$icon_work_dir/Dust3DViewer.iconset" -o assets/app-icons/Dust3DViewer.icns
rm -rf "$icon_work_dir"
./script/check_app_icons.sh
```

The generator draws at every standard 16–512 point size at 1× and 2×. Verify the
packaged bundle's icon declaration and signed resource after rebuilding; Dock
appearance remains a manual native check.
