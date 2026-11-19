# App animation-family fixtures

These bounded documents exercise the optional native App owner-copy and CPU
skinning route. Four fixtures come from Core-authored modeling example JSON
specifications. Insect, Snake and Spider are synthetic body chains. They have no
upstream Qt differential-corpus provenance.

`manifest.json` records the exact Core generator revision, generator/source/archive
SHA-256 hashes, authored clip IDs, durations and frame counts. `Sources/` preserves
the input specifications. Each archive is bounded to 128 KiB. `LICENSE` retains
the Core source's MIT license. The synthetic chain specifications are MIT project
additions.

Reproduce using a checkout of Core `0d93595fb359de8eecfd33046d1a7b09eafee46d`.

```sh
python3 -B script/tests/generate_animation_family_fixtures.py --core /absolute/path/to/core
python3 -B script/tests/generate_animation_family_fixtures.py --core /absolute/path/to/core --verify
```

Generation performs document serialization using the pinned source generator.
The optional `NativeAnimationFamilyBridgeTests` tests use both
`MOTE3D_EXPERIMENTAL_FISH_IDLE` and `MOTE3D_EXPERIMENTAL_GENERATED_RIG`. They retain
the existing short authored Fish regression and add one moving and one idle clip
per family. They check copied source identity, actual deformation over bounded
quarter samples, finite/stable mesh channels, audible versus silent PCM and copied
results surviving a later native load.

Selected FBX animation-stack decoding, all clips and parameter combinations,
independent Qt numerical comparisons, physical playback/rendering and VoiceOver
remain separate acceptance work. A native smoke or these representative cases
does not establish complete animation parity.
