# ADR 0083: Mixed materials in the editor

Status: Accepted

## Context

The shared archive-material service selects source-aware baking when imported
and procedural geometry coexist. The editor still selected authored imported
rendering for these documents, omitting procedural image baking. The editor
already owns revision-bound material state and a renderer that accepts the
source-baked representation. Tracked in #173 as part of M4 (#143).

## Decision

Use `ArchiveMaterialPreparationService` in the existing editor material task,
passing the exact encoded snapshot once. Keep substitutable imported, procedural
and source baking boundaries for lifecycle tests. Keep
`MeshPreviewState<MeshMaterialContent>` as the sole material state; the source
accessor derives from current, nonfailed content just like the existing accessors.
No new renderer or document/history path is introduced.

A confirmed current source-baked frame satisfies supported imported, baked and
procedural-detail notices through the distinct source-baked capability. Ordinary
legacy bakes retain their surface-detail limitation; unknown diagnostics and
original errors remain visible. A fixture with retained wrapWrinkles=0 metadata
covers the acknowledgement boundary without adding an active wrinkle effect. Scope/revision guards reject stale results and callbacks. Failure keeps
ordinary geometry; retry uses the unchanged snapshot. Material-only edits refresh
maps without resetting ordinary geometry, selection or camera.

## Verification and remaining work

Focused tests cover real mixed surfaces, current-frame publication, original
source/GPU errors, replacement, stop, empty output and exact retry inputs. Geometry
and material-only edits preserve selection/camera, exact undo/redo and save/reopen,
including original imported GLB, procedural PNG and opaque asset bytes. Native
inspection displays both textured surface kinds in the 20-triangle fixture.
Screenshots are external diagnostics, not committed rendered baselines.

The shared service's repeated mixed inspection and independent resource quotas
remain as documented in ADR 0082. macOS preview adoption, chart-isolated mipmaps,
textured export and broader M4 acceptance remain separate stages. Full native
editor parity is not claimed.

Coverage remains scoped as in the coding-standards audit. Earlier local checkpoint
measurements were 100% line/region coverage for shared preparation and 88.81% lines /
78.25% regions for the existing EditorStore in an 838-test run. Those are historical,
not measurements of this revised integration; inspect the current gate report.
The existing EditorStore does not meet the general 95% application target. Controller/native UI coverage remains a
release-hardening gap under #147 and must not be described as fully covered.
