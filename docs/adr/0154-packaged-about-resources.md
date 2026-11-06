# ADR 0154: Resolve packaged About resources independently of SwiftPM

Status: Implemented; full gate and review tracked separately

## Decision

The installed rendering bundle lives under Bundle.main.resourceURL. Resolve it
before considering Bundle.module, whose generated absolute build fallback may
terminate on another machine. A packaged .app with missing resources returns nil
for existing visible error presentation and never consults that fallback.
Command-line/development hosts retain lazy SwiftPM resource loading.

Keep lookup in a small Foundation helper and leave AppKit panel lifecycle intact.
The isolated archive gate compiles the actual production About/options/helper
sources into an owned metadata-only executable inside extracted app copies. Its
instrumented module accessor has no original build path; any consultation fails
validation normally, without intentionally terminating a product process. Exact
license inclusion and zero development lookups are required for Editor/Viewer.
No GUI executable, panel, protected app, native engine or writer is run. Original
archives remain immutable; this proves resource routing, not physical acceptance.
