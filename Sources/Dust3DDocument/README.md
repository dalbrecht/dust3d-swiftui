# Dust3DDocument

`DocumentHistory.previewIdentity` exposes separate process-local `geometry` and
`materials` identities for accepted preview inputs. Compare these values before
and after commands or Undo/Redo to invalidate only the affected output. History
restores the identities with exact document bytes; fresh history instances remain
independent. They never enter archive data or replace request/scope admission.
Unknown command kinds conservatively invalidate both inputs. See
[ADR 0116](../../docs/adr/0116-history-owned-preview-sources.md).

Lossless `.ds3` archive values, graph commands, and bounded snapshot undo/redo. This SwiftPM library uses Foundation XML and has no UI or Qt dependency. Build and test from the repository root with `make ci`.

Initialize `Dust3DDocument(data:)`, inspect `editorContents()` or `modelXML`, apply typed `DocumentCommand` values, and write `encoded()` atomically through the application's file service. Unchanged archives remain byte-identical; commands retain unrelated XML and binary assets. Invalid commands throw `DocumentError` without replacing the original value.

Graph removals are low-level building blocks. Discover `partSplitRequirements(for:)` after a removal, inject fresh `PartSplitIdentity` values, and compose `.splitPart` with that removal in a `DocumentHistory` transaction. The editor's `EditorSession` automates this orchestration off the main actor. UUID generation is deliberately excluded from document/state commands. Requirements are recomputed when a split command runs, so stale or insufficient identity plans fail atomically.

Splitting retains the largest connected group's existing identity (ties follow node order), copies part/component style and unknown metadata for additional groups, and preserves assets and unaffected hierarchy. New IDs must be unique, nonempty and at most 128 UTF-8 bytes; the app supplies standard UUIDs. Component references are copied in document order. Actual child components stay on original references to avoid duplicating geometry.

Archive parsing caps archives at 256 MiB and model XML at 16 MiB, with bounded XML depth. Editor graph reads allow 10,000 nodes and 20,000 edges; splitting additionally caps total parts/components at 10,000, with operation-specific validation. Splitting rejects excessive part/component counts and copied metadata before allocation; its metadata-size estimate is conservative near the model limit. History defaults to 100 entries and 64 MiB. These limits do not bound CPU/memory inside inherited C++ geometry algorithms.

See [splitting decision](../../docs/adr/0009-disconnected-part-splitting.md) and [verification](../../docs/part-splitting-verification.md). Use `.joinNodes(id:from:to:)` to connect editable chain endpoints within or across parts. The source part settings win when consuming a target part; target leaf component settings are consumed, while actual child components survive as groups. Node/edge IDs, unrelated metadata and assets remain intact. Known `cutFace` links are redirected, and resulting profile cycles throw `DocumentError.cyclicProfile` atomically. Unsupported branching/disconnected results, self/duplicate edges and read-only endpoints are rejected. Raw `.addEdge` remains a lower-level same-part primitive. See [joining decision](../../docs/adr/0010-cross-part-joining.md) and [verification](../../docs/part-joining-verification.md). Empty-part cleanup and full Qt parity remain pending.


Selected-node clipboard foundations use `document.copyingNodes(ids)` to obtain a `NodeClipboard`. It contains selected graph objects, ancestor component groups and complete transitive linked-profile dependencies; `selectedNodeIDs` excludes dependency nodes. All source assets are retained because opaque fields may reference them. Unrelated source model objects are excluded from destination insertion.

Supply a fresh identity for every entry in `clipboard.identifiers`, then apply `.pasteNodes(clipboard:identities:offset:)`. IDs are globally unique across semantic node/edge/part/component objects, nonempty and at most 128 UTF-8 bytes. Conservative collision checks treat UUID aliases with/without braces as the same identity. Profile references, however, require an exact part-ID spelling after UUID-shape classification; unresolved values stay unchanged. Linked-profile target replacements must remain UUID-shaped. The offset is explicit and must yield valid finite geometry. Known references are classified using the inherited engine’s UUID semantics and remapped; unknown text and named cut-face presets stay unchanged. Native graph elements adopt the destination canvas namespace, while opaque extensions retain inherited source bindings. Asset metadata comparison includes those bindings. Destination root/container settings and unrelated data survive. Equal asset entries are shared; differing content/type/metadata for an existing name throws `DocumentError.conflictingAsset` atomically. `DocumentHistory` provides exact one-step undo/redo including imported assets.

The document layer has no system pasteboard or UI dependency. Native integration uses `EditorSession.copyPayload` and `paste(data:)` in the editor-model package. `clipboard.partSplitRequirements()` sizes construction-time splits, including read-only copied parts; map each source part ID through `identities` and inject fresh `PartSplitIdentity` values using `.pasteNodes(..., partitions:)`. Partition keys must identify newly pasted parts, and split IDs cannot collide with existing/imported identities. Construction can partition new readonly copies while ordinary `.splitPart` retains read-only protection. Part settings, component metadata and assets remain in the same exact undo transaction.

The default empty partition plan remains a low-level building block; a disconnected selection needs its discovered partitions before engine generation. The actor always supplies them. Native Cut/Copy/Paste and save/reopen validation now have [verification](../../docs/native-clipboard-verification.md); the original [foundation record](../../docs/clipboard-foundation-verification.md) describes that earlier stage. Qt snapshot-text clipboard interoperability remains a separate adapter task.

Reference-image storage uses Qt's `asset` named `canvas.png`. `referenceImagePNG` returns its unchanged opaque bytes, or nil when absent/not an asset. Apply `.setReferenceImagePNG(data)` to replace/add PNG bytes, or `.setReferenceImagePNG(nil)` to remove the image. No-op commands preserve every original byte. Existing target metadata survives replacement; unrelated header/model/assets/gaps/trailing bytes survive all operations. A conflicting non-asset name rejects with `conflictingAsset`; non-PNG signatures throw `invalidReferenceImage`; encoded images above 32 MiB or archive/history bounds throw `limitExceeded` atomically.

Callers must fully decode, validate pixel/resource limits and convert imported images to PNG before sending the command. The document library checks the signature and encoded-size boundary, without importing an image framework or asserting full raster validity. Existing invalid/unsupported image bytes remain preserved on ordinary open/save. Asset-only and mixed transactions participate in undo/redo; asset-capable net-zero comparisons include all asset bytes and header metadata in addition to model data. Model-only transforms/topology edits retain their model-only path, avoiding scans of unchanged opaque assets. See [the storage decision](../../docs/adr/0015-reference-image-archive.md).

`hasReferenceImage` and `referenceImageByteCount` inspect slot metadata without copying payload data. The app uses the byte count to reject oversized existing references before decoding/materializing them; the original document still retains those bytes for lossless saving.

`editorContents().parts` exposes ordered immutable part IDs, legacy names and visible/locked/disabled flags. `.setPartName(id:name:)` changes only the legacy part name (empty removes it), caps input at 1024 UTF-8 bytes and rejects controls/newlines with `invalidPartName`. `.setPartState(id:property:value:)` changes a known flag, including restoring inactive parts. Missing IDs throw `missingPart`; semantic no-ops preserve bytes, and unknown metadata/assets/component names remain unchanged. See [the part decision](../../docs/adr/0017-native-part-state.md).

`try document.origin()` returns a complete finite origin within ±1,000,000, or nil for missing/unsupported original fields. `.setOrigin(NodePosition)` validates all axes and changes only canvas originX/Y/Z; invalid edits throw `invalidOrigin` without changing history. Zero/negative values are valid. No-op and net-zero transactions preserve original bytes/redo; ordinary saving never repairs or settles unavailable origins implicitly. Node positions and unknown XML/assets remain unchanged. Origin changes affect generated mesh placement and require preview regeneration. See [verification](../../docs/document-origin-verification.md).

`editorContents().origin` publishes that same supported-value query alongside graph/part metadata without another archive parse.

`.pruneEmptyParts(ids)` explicitly removes requested empty editable parts, their leaf component references and known cut-face links to deleted profiles. Surviving nested/unknown component content remains as groups; matching references are processed bottom-up; every asset is retained. Missing/duplicate/nonempty/readonly targets throw `DocumentError.invalidNode` atomically; empty input preserves original bytes. Low-level node removal still retains empty owners until this command is applied. Use `EditorSession` for deletion plus splitting/cleanup in one undo transaction. Example: `let cleaned = try emptied.applying(.pruneEmptyParts([partID]))`. See [decision](../../docs/adr/0024-empty-part-cleanup.md).

Qt clipboard text uses bounded UTF-8 canvas XML. Native Copy offers richer native data first and a graph-only text fallback; plain text cannot transfer embedded asset bytes or distinguish selected nodes from profile dependencies. Paste validates and remaps the graph in one undo step. See [verification and pending native/Qt acceptance](../../docs/qt-clipboard-verification.md).

```swift
let document = try Dust3DDocument(snapshotXML: xmlData)
let nodes = try document.editorContents().nodes
```

The initializer preserves exact model XML and unknown fields, validates editable data, and throws typed document errors for malformed/oversized input. Use `init(data:)` for full asset-bearing archives.

`try document.components()` reads immutable component values in XML preorder. `parentID` and ordered `childIDs` describe the actual nested hierarchy; `linkDataType`/`linkData` preserve unknown source links and `partID` interprets only `partId`. Absent/empty/duplicate identities, duplicate containers, unsupported child tags carrying IDs or more than 10,000 components reject this explicit query. Ordinary archive saving continues preserving opaque hierarchy XML.

Example: `let roots = try document.components().filter { $0.parentID == nil }`. Apply `.setComponentName(id:name:)` to rename independently of the linked legacy part. Input is trimmed, bounded to 1024 UTF-8 bytes and rejects controls/newlines with `invalidComponentName`; missing IDs throw `missingComponent`, malformed hierarchies throw `invalidComponent`. Empty names remove the attribute, no-ops retain original bytes, and existing history/session transactions retain exact undo/redo. See [ADR 0031](../../docs/adr/0031-component-hierarchy-foundation.md). Tree UI and structural edits follow separately.

Apply `.reorderComponent(id: componentID, direction: .up)` (also `.down`, `.first`, `.last`) to move a component among its current siblings without changing parent or descendants. `ComponentOrderMove.destinationIndex(from:count:)` resolves a final index, returning nil for invalid input/no-op boundaries; for example, `.last.destinationIndex(from: 0, count: 3)` returns 2. Missing identities throw `missingComponent`; ambiguous/unsupported hierarchy throws its existing typed error. Boundary moves preserve bytes/redo; real moves retain opaque sibling slots, subtree metadata and assets. As in upstream, part state flags do not prevent sibling ordering. See [ADR 0033](../../docs/adr/0033-component-sibling-order.md).

Structural commands operate on the validated hierarchy independently of unsupported node geometry:

```swift
let grouped = try document.applying(.groupComponents(ids: [firstID, secondID], groupID: freshID))
let moved = try grouped.applying(.reparentComponent(id: otherID, parentID: freshID))
let promoted = try moved.applying(.ungroupComponent(id: freshID))
```

Grouping accepts nonempty unique siblings, uses their source order and inserts a new unnamed group at their first slot. New IDs must be nonempty, unique among supported semantic node/edge/part/component identities (including braced/unbraced UUID aliases), at most 128 UTF-8 bytes and free of whitespace/control/non-XML scalars. `DocumentComponent.isGroup` recognizes only empty/absent link kind and data. Reparent appends a subtree to a supported unlinked group or to the root (`parentID: nil`); self/descendant cycles reject with `invalidComponentStructure`. Missing IDs throw `missingComponent`; component count/encoded-size limits throw `limitExceeded`, and malformed/over-depth output throws the existing XML error. All failures leave the source archive unchanged.

Ungroup intentionally removes the group's own identity and settings while promoting all child XML at its position. Assets and unrelated fields survive; Undo restores the removed group metadata exactly. Groups with no parsed XML children and same-parent moves are exact no-ops retaining redo. Grouping/ungrouping nonconsecutive siblings is not an inverse ordering operation: use Undo for exact restoration. Part-linked/opaque components can be moved/wrapped intact but are not valid destinations, parents receiving grouped/promoted children, or ungroup targets. Moving a subtree out of such an unsupported parent remains available. See [ADR 0034](../../docs/adr/0034-component-structure-foundation.md). Native structural controls follow separately.

Structural detachment preserves inherited default, prefix and QName-value namespace bindings. Mixed default namespaces remain visible to component hierarchy/order queries. Namespace expansion is bounded per structural operation to 100,000 added bindings and 16 MiB of prefix/URI payload plus per-binding overhead; excess expansion throws `limitExceeded` before publication. Unknown extension IDs are not reinterpreted as graph identities.

`DocumentComponent.combineMode` reports a known effective mode (including legacy
component `inverse`), or nil for an unknown source mode.
`document.applying(.setComponentCombineMode(id: id, mode: .normal))` explicitly
changes one mode and clears legacy component inversion; semantic no-ops retain
archive bytes and redo. Missing/ambiguous component identities throw typed
`DocumentError` failures. Unknown unrelated XML and assets remain intact.

`DocumentComponent.smoothCutoffDegrees` reports a finite 0–180-degree cutoff,
zero when missing/empty, or nil for unsupported source values.
`.setComponentSmoothCutoffDegrees(id: id, degrees: 90)` changes normals without
changing geometry; zero removes the attribute on an actual edit. Invalid input
throws `DocumentError.invalidComponentSmoothing`; unknown unrelated data and
semantic no-op bytes remain intact.

`part.modifierValue(.subdivision)` reads a supported procedural flag, or nil for
unsupported source metadata. `PartModifierProperty` includes subdivision, chamfer,
rounded ends, interpolation and hard joins; interpolation defaults on.
`.setPartModifier(id: id, property: .roundedEnds, value: true)` changes one flag
without changing source graph, unrelated properties or assets. Missing parts
throw `DocumentError.missingPart`; semantic no-ops retain exact bytes and redo.

`part.deformationScale(.width)` and `.thickness` read finite 0...2 cross-section
scales (one when absent), or nil for unsupported/ambiguous metadata.
`part.isDeformationUnified` reads the known flag (false when absent) or nil.
`.setPartDeformationScale(id: id, property: .width, value: 0.995)` preserves fine
nondefault values; `.setPartDeformationUnified(id: id, value: true)` toggles
maximum-node-radius deformation independently. One/false restore absent defaults
on actual changes. Nonzero subnormal doubles are rejected by the parser. Nonzero values must also
stay nonzero and finite in the engine Float; explicit zero remains supported.
Underflowed source literals remain preserved as unavailable until replaced.
Invalid scales throw `DocumentError.invalidPartDeformation`;
missing parts throw `missingPart`. Semantic no-ops retain source bytes and redo.

`part.cutFace` reads a `CutFaceSelection` preset or exact linked-part identity,
Quad when absent/empty, or nil for unsupported metadata. An imported linked ID
can remain unresolved without rewriting the source. `part.cutRotation` reads
finite normalized half-turns retained by the engine Float in -1...1 (zero when absent/empty),
or nil for unsupported metadata; 0.25 means 45 degrees.
`.setPartCutFace(id: id, selection: .preset(.triangle))` or `.linkedPart(profileID)`
changes only the part's cross-section, requiring an existing engine-compatible
profile identity and rejecting newly introduced part/node dependency cycles.
Unrelated imported cycles do not block presets or independent links. Reapplying
an unchanged unresolved imported profile is a byte-preserving no-op. Invalid identities
throw `invalidPartCutFace`, missing owner/target throws `missingPart`, and cycles
throw `cyclicProfile`. `.setPartCutRotation(id: id, rotation: 0.005)` retains fine
rotations; invalid input throws `invalidPartCutRotation`. Exact zero removes the
attribute on actual edits. No-ops retain original bytes/spellings and redo.

`DocumentPart.canBeCutFaceProfile` reports whether the exact source identity
passes the inherited engine's profile-link classification. It reuses the same
classification as the cut-face command; it does not normalize, rename or discard
legacy IDs. UI candidate lists must exclude false values.

`DocumentPart.target` reads Model, CutFace, StitchingLine or StitchingLoop.
Absent/empty target metadata means Model; unknown values and ImportedModel
remain nil and byte-preserved. `.setPartTarget(id:target:)` explicitly replaces
the role, preserving nodes, flags, assets and unrelated metadata. Model removes
the attribute only when a semantic change is needed; no-ops retain exact source
spellings and redo. Missing owners throw `DocumentError.missingPart`. Example:
`.setPartTarget(id: part.id, target: .cutFace)`. Imported model role creation
requires the separate embedded-model pipeline and is not offered here.

`DocumentComponent.stitching` exposes optional closure flags, target segment
count and loop-cap scalars. `.closureValue(.front/.back/.side)` defaults to false;
`.scalarValue(.depthRatio)` defaults to 1 and `.sharpness` to 0; absent
`targetSegments` means automatic (0). Unsupported values remain nil. Empty
numeric metadata remains unsupported because inherited importer/generator
interpretations differ or fail; it is not silently repaired. Segments accept
whole integer spellings from 0 through 100. Scalars use the bounded, comma-aware
engine-compatible numeric parser, rejecting nonzero values that become Float zero.

Commands `.setComponentStitchingClosure(id:property:value:)`,
`.setComponentTargetSegments(id:segments:)` and
`.setComponentStitchingScalar(id:property:value:)` preserve every unrelated node,
part, component, opaque field and asset. No-ops preserve bytes and redo; explicit
defaults remove only a changed attribute. Missing owners throw `missingComponent`;
invalid numbers throw `invalidComponentTargetSegments` or
`invalidComponentStitchingScalar`. Example:
`.setComponentStitchingScalar(id: group.id, property: .depthRatio, value: 0.5)`.

`DocumentPart.isLoopInteriorFilled` reads `fillLoopInterior`: absent/empty means
false, supported true/false spellings stay known, and unknown text remains nil.
`.setPartFillLoopInterior(id:value:)` explicitly changes only that attribute.
False removes a changed attribute; no-ops preserve exact source spelling/redo.
Missing owners throw `DocumentError.missingPart`. Node locks/visibility/disabled
flags, source graph, role, opaque metadata and assets survive. Example:
`.setPartFillLoopInterior(id: part.id, value: true)`. The engine consumes the flag
only for isolated closed stitching loops, not loops already bordering a surface.

### Group wrapping

`component.wrapping` exposes known Skin/Cloth/disabled modes, keep-children,
64...20000 face counts and bounded geometry scalars. Nil values preserve
unsupported source text; absent/empty values use inherited mode defaults.
`.setComponentWrapMode(id:mode:)`, `.setComponentWrapKeepChildren(id:value:)`,
`.setComponentWrapFaces(id:faces:)` and `.setComponentWrapScalar(id:property:value:)`
reject non-group owners and invalid edits with typed errors. For example:
`.setComponentWrapScalar(id: group.id, property: .offset, value: 0.01)`.
Mode changes retain explicit parameters. Semantic no-ops retain archive bytes
and redo; edits remain compatible with exact history and actor-session batches.
Existing higher face counts, binding, patterns and wrinkle metadata stay intact.
Core issue #13 tracks nonfinite low-density opening output; this document
foundation does not claim complete wrapping geometry or native UI acceptance.

## Part material parameters

Read `part.materialValue(.metallic)` (or `.roughness`/`.emissive`); nil means
unsupported source metadata. Apply `.setPartMaterial(id: id, property: .roughness,
value: 0.5)` through document/history commands. Metallic and roughness accept
0–1, emissive 0–2, matching the reference editor. Invalid values throw
`DocumentError.invalidPartMaterial`; missing identities throw `missingPart`.
Semantic no-ops retain exact bytes/redo; real default edits remove only that
attribute. Unknown XML/assets and exact undo/save preservation remain intact.
See [verification](../../docs/part-material-verification.md).

## Component colors

`component.color` distinguishes `.unset`, `.value(DocumentColor)` and
`.unsupported(originalText)`. `DocumentColor(archiveValue:)` accepts strict
`#RRGGBB` / `#AARRGGBB` (alpha first), or returns nil for unsupported input.
Construct channel values with `DocumentColor(red:green:blue:alpha:)` using UInt8.
Apply `.setComponentColor(id: id, color: color)`; nil removes only the explicit
color. Missing identities throw `DocumentError.missingComponent`; semantic no-ops
retain exact source spellings/bytes and redo. Untouched unsupported colors remain
lossless. See [verification](../../docs/component-color-verification.md).

Clipboard graph insertion and asset/header merging share one namespace
materialization quota: 100,000 installed bindings and 16 MiB of UTF-8 prefix/URI
payload plus a logical 16-byte charge per binding. Explicit default replacements
count too. Exceeding either quota throws `DocumentError.limitExceeded` before the
next binding set is allocated, without publishing a partial document or history
entry. Existing source/archive limits still apply; this is not a process RSS cap.
See [ADR 0067](../../docs/adr/0067-bounded-namespace-transfers.md).

Component color images expose missing/reference/unsupported source state through
`DocumentComponent.colorImage`. Assign an existing retained image with
`.setComponentColorImage(id:imageID:)`, or pass nil to remove the override while
retaining all assets. `.importComponentColorImage(id:imageID:png:)` atomically
inserts bounded encoded PNG bytes and assigns a caller-supplied identity. Exact
alias no-ops retain source spelling and redo; conflicting resources reject without
publication. Import plus assignment is one history step, including asset bytes.

`PNGContainerMetadata(data:)` provides the shared pure envelope/quota boundary used
by imports and Dust3DKit's existing decoder. It does not decompress samples or
validate CRCs; platform image validation remains necessary before user imports.
See [ADR 0068](../../docs/adr/0068-lossless-component-color-images.md) for identity,
resource, transaction and remaining native-import requirements.

## Stored rig parameters

`try document.rigSettings()` reads canvas template intent with exact source text.
`DocumentRigType` recognizes None, Biped, Quadruped, Bird, Fish, Snake, Insect and
Spider from the inherited Qt template resources. Missing/empty values mean disabled;
unknown spellings remain `rigType == nil` with `sourceRigType` retained. Recognition
is not a claim that native generation supports the template.

Apply `.setRigType(.biped)` or `.setHeadHasEyelids(true)` through DocumentHistory
for undoable edits. These commands change only their canvas attribute; unrelated
rig/animation XML and assets survive. Semantic no-ops retain original bytes and
redo, including legacy boolean spellings. Eyelids use inherited true/True/1
semantics; changing to false removes the attribute. Reading/editing never invokes
an engine, skeleton, pose, or animation evaluator. See ADR 0091 and issue #246.

## Stored edge bone bindings

`DocumentEdge.boneName` retains the exact inherited lookup name, or an empty string
when unassigned. `.setEdgeBoneName(id: edgeID, name: "Root")` assigns that intent;
an empty name removes the attribute. New names are limited to 1024 UTF-8 bytes and
reject controls/newlines. Names are not trimmed or case-normalized because template
lookup is exact. Legacy values, including longer unsupported names, survive reads
and unrelated edits. Both endpoints must be editable under existing part flags.

The command preserves unrelated edge/rig XML and assets, uses exact snapshot
undo/redo, and does not invoke generation or prove the named bone exists. Editor
snapshots carry the same intent through their existing edge array. See #247 and
ADR 0092; actual rig evaluation and native binding controls remain M5 follow-up.

Bone lookup identities compare exact UTF-8 spellings. `BoneNameIdentity` provides
that equality for stored names and editing drafts, and
`edge.hasExactBoneName(candidate)` checks a snapshot without Unicode canonical
normalization. `DocumentEdge` equality retains byte-distinct names. Applied edits
still use the document command's validation and exact undo/redo behavior.

`animations(maximumCount:)` reads source-ordered stored intent, including unknown
types and missing name/type fields. Animation create/name/type/parameter/duplicate/
delete commands participate in exact document history and retain opaque XML/assets.
IDs and parameter lookup compare UTF-8 bytes. Reserved xmlns is never an editable
parameter. These APIs do not evaluate clips, rigs, sound or timing; core #95 stays
quarantined. ADR 0104 documents quotas, unsupported metadata and remaining UI/
native acceptance. Call document work on the existing editor actor, not the UI.
