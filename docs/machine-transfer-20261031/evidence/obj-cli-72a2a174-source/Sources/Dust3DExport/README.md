# Dust3DExport

Headless geometry-only OBJ export using the same bounded SDK and coordinated
atomic writer as the native editor. No application window is created.

Build with `./script/swift.sh build --product Dust3DExport`. The executable is in
`$DUST3D_BUILD_ROOT/build/debug/Dust3DExport` when using an explicit build root.
Run `Dust3DExport model.ds3 --output model.obj`; relative paths resolve against
the current working directory. `--input`, `-o`, `-output`, `--output`, `--help`
and `-h` are supported. Use `--` before a positional input beginning with `-`.
One input/output pair is admitted per invocation; formats other than OBJ fail.
There are no new dependencies or configuration files.

Success writes one JSON object to stdout containing destination, byte count,
vertex/triangle counts and original source warnings. Stderr contains JSON-line
progress and errors; inherited native text diagnostics can also appear there.
Exit status is 0 for success/help, 2 for invalid arguments, 1 for an operational
failure, or 130 for cooperative SIGINT cancellation before commit. Diagnostics
identify reading, generating, writing or reporting and preserve original causes.
A reporting failure after commit includes `committedDestination`; do not infer
that nonzero status always means no file was committed.

The SDK reads bounded archive data, regenerates complete source geometry and
copies owned OBJ bytes. The existing file service coordinates access, stages
on the destination volume and replaces atomically. SIGINT cancels the Swift
task; synchronous native generation finishes its current phase before cancellation
is observed. A successful commit wins a late cancellation. SIGTERM uses normal
OS termination semantics. This command does not implement batch processing,
textures/materials, rigs, animation, GLB, FBX or WAV.

Development: `./script/swift.sh test --filter Dust3DExportTests` and `make ci`.
Process tests exercise real archive export and SIGINT while a coordinated reader
holds the destination. See ADR 0096 for stdio ownership and remaining scope.
