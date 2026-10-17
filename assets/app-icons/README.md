# Temporary app icons

The editor has a teal cube marked **E**; the viewer has a blue cube marked **V**.
These original geometric placeholders identify the local apps in the Dock and Finder
until final artwork is designed. The `.icns` files are app resources, not snapshot
baselines. They use the repository's MIT license.

`script/build_and_run.sh` copies the appropriate icon into each bundle and declares
`CFBundleIconFile` before ad-hoc signing. Rebuild through that script to see the icon.

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
