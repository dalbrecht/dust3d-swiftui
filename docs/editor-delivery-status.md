# Native editor delivery and acceptance status

Snapshot: October 30, 2026. The full scope remains
[editor-port-plan.md](editor-port-plan.md), including M0–M8. This snapshot separates
implemented stages, local work and missing acceptance; it is not a parity signoff.

## Public and local baselines

- Apple public master at this delivery base: `bf33b8d335f90a04af748822772444842ea3a2b3` (procedural FBX export, #287).
  Crop adjustment (#249) and the native node-ID accessibility/copy fix (#251) are
  merged, as are the stored rig document/actor foundations (#253), inspector (#255) and exact edge-bone assignments (#256). Historical modifier/clipboard QA used clean implementation `2011b362`;
  later documentation and test commits do not retag that captured runtime.
- Core PR [#212](https://github.com/dalbrecht/dust3d-core/pull/212) is merged at
  `48b0ce2d6d61cf58731bb0c3e14ef5965a686d68`, following completed exact-head review
  and six green CI checks. The development XPC host now uses the C request
  coordinator's current-source admission. Its healthy fixture has one immutable
  source, connection and job; this does not establish editor adoption, active
  stop/escalation behavior or complete containment.
- Apple pins reviewed core `48b0ce2d6d61cf58731bb0c3e14ef5965a686d68` through
  merged dependency PR #273, explicitly authorized by the user.
  Local core contracts and helper tests are not evidence of Apple adoption.
- Every public PR still requires its full local gate, completed exact-head
  automated review, addressed feedback and all green CI before serial merging.
  A stale running summary is not proof of worker liveness. The user authorizes
  one fresh recovery review request per unchanged head before prompting; further
  recovery requests on that head still require a decision.

## Modeling-focused beta work

The [roadmap project](https://github.com/users/dalbrecht/projects/5) tracks the
modeling beta, functional-parity candidate and release candidate across the Apple
and core repositories. The estimates remain rough ranges, with no committed due
dates. A milestone assignment does not mean its acceptance has passed.

The following October 30 results distinguish public delivery from local work:

| Work | Current evidence | Remaining acceptance |
| --- | --- | --- |
| Export warning identity (#235), opt-in owned source mip copying (#179) | Draft [PR #288](https://github.com/dalbrecht/dust3d-swiftui/pull/288), head `5b43ed72`; all three hosted checks succeeded at that head. Ordinary source loads remain base-only. | Review and merge decisions; native warning/VoiceOver acceptance; broader mip integration. |
| Node drag admission (#245) | Two local commits capture document/revision, selection generation, locks, projection and pointer identity; [verification](node-drag-verification.md). The combined app gate at `8fe106f1` passed 1,124 XCTest cases, coverage, Qt-free linkage and signed bundle rebuild. | Physical pointer routing, held-gesture cancellation and VoiceOver on the final implementation. Local commits are not merged. |
| Local core integration (#178) | [Isolated tooling](local-core-integration.md), local commits `df3c6b48` and `3c23d54c`. Pinned `make ci` passed 1,102 XCTest cases before the final Python-only hardening; all 15 final orchestration tests and the linked-identity executable fixture passed afterward. | Publication/review; this tool does not replace the pinned gate or authorize a dependency update. |
| App/core mip interoperability (#179/core #59) | Local combined app `3336c8df` and core `83be6278` passed exactly `SourceBakedLoaderTests.testOptInMipBakeCopiesOwnedLevelsAndEnforcesCopyBudget` using the licensed procedural Capsule. The linked XCTest image matched all 335 generated identity bytes, including both revisions and source digests; both inputs were clean and the production manifest/pin stayed unchanged. | Mixed imported/procedural documents, useful mip retention through app state and GPU sampling, export parity, core review and exact dependency update. This single test does not enable #180. |

Core mip corrections through local `83be6278` have five audited synthetic CTest
targets passing, covering fallback, UV packing, base isolation, padded atlas and
warning behavior. These tests do not establish mixed-archive, GPU or full legacy
acceptance. Earlier broad CTest selection included excluded legacy fixtures and
must not be treated as a quarantine-compliant gate. No excluded legacy suite is
required by the focused local integration test above.

Local follow-ups `c21ee368` and `e781c631` preserve the padded-atlas cause when a
base-atlas retry fails with a generic exception, including the nested original
exception. The native engine build, quarantine source guard and two audited
synthetic targets passed. Allocation failures retain the limit-exceeded mapping
by source inspection; no allocation-failure probe was run, and diagnostic
construction cannot guarantee recovery under actual memory exhaustion.

Hollow thickness (#96) remains incomplete. Historical builder evidence establishes
an inward shell and terminal rims, including collapsed inner geometry at thickness
one; it does not establish compatibility with the current position-keyed UV/source
pipeline. The policy for unrepresentable inner geometry remains a user decision.
No working hollow control or production dependency change has been introduced.

## Milestone evidence and gaps

| Milestone | Evidence established | Acceptance still open |
| --- | --- | --- |
| M0 — Viewer/baseline | Separate viewer and native editor products; shared standards and maintained MIT downstream. Selected ordinary Qt CPU comparisons are recorded in core issue #35. | Complete action/serialization inventory and broad licensed differential corpus; selected CPU cases are not full Qt GUI/export parity. |
| M1 — Document/persistence | Lossless document/undo foundation, bounded archives, typed errors and save snapshot guard: [foundation](editor-foundation-verification.md), [native save](native-save-snapshot-verification.md). | Qt reopen of native-created corpus, broader recovery/close-cancel and physical filesystem acceptance. Simulated write failures do not prove all OS failures. |
| M2 — Canvas/editor | Node/edge creation/deletion/history, selection/transforms, front/side editing, references, separate windows; crop adjustment is merged in #249. Controlled two-window/drag evidence is tracked in [#245](https://github.com/dalbrecht/dust3d-swiftui/issues/245). | Native-created capsule and multi-part sword reopened in Qt; held-gesture Escape, responsiveness/stale-result scenarios, keyboard/VoiceOver/older macOS. |
| M3 — Modeling | Hierarchy/modifier document/controller suites and scoped native checks, now including [controlled thickness/unified and intersecting hard-join history/reopen](controlled-native-modifier-acceptance.md). | Broader linked topology interactions/replacements, remaining families and Qt comparisons. Hollow-thickness consumer gap remains [#96](https://github.com/dalbrecht/dust3d-swiftui/issues/96); [#120](https://github.com/dalbrecht/dust3d-swiftui/issues/120) stays open. |
| M4 — Materials/imports | Existing material/import/bake/render stages have [editor evidence](imported-material-editor-verification.md) and [file-preview evidence](mixed-file-preview-verification.md). | Mixed source mip adoption [#172–180](https://github.com/dalbrecht/dust3d-swiftui/issues/172), full alpha/PBR/UV/export parity and malformed-asset containment. Historical render evidence does not enable the quarantined experimental catalog. [#143](https://github.com/dalbrecht/dust3d-swiftui/issues/143) remains open. |
| M5 — Rigging | Stored-parameter document/actor commands (#246/#253) and inspector controls (#254/#255) are merged. Edge-binding commands and controls (#247/#256) are merged, including exact UTF-8 identity and owned native field Return/Escape tests. Historical whole-app Save/history/reopen was not established after control timeouts. These stages do not establish native rig evaluation. | Rig/pose ownership, skeleton/hierarchy/weights, IK and native save/keyboard acceptance under [#144](https://github.com/dalbrecht/dust3d-swiftui/issues/144) and its staged issues. Preserve Apple #199 quarantine. |
| M6 — Animation/audio | Stored-animation document commands, list snapshots, actor coordination and inspector are merged (#265–268). These edit retained metadata; no native evaluation/playback/audio acceptance exists. | Bounded pose/audio copies, time-based playback, synchronization and WAV workflows under [#145](https://github.com/dalbrecht/dust3d-swiftui/issues/145). Preserve core #95 quarantine. |
| M7 — Export/batch | Original procedural geometry OBJ (#282) and FBX (#287) workflows are merged, with current-revision publication, injected lifecycle tests and [independent ordinary FBX consumer evidence](fbx-export-verification.md). | Native panels/keyboard/VoiceOver, broader geometry, imported/mixed and textured outputs, GLB/WAV, rigged/animated exports and headless/batch acceptance under [#146](https://github.com/dalbrecht/dust3d-swiftui/issues/146). |
| M8 — Release/hardening | Measured Swift suites, explicit Qt-free builds, file-preview integration stages and local core mitigation contracts. | Strong memory/descendant/filesystem/network/parent-death containment, active lifecycle evidence, trusted packaging/signing/notarization, hardware/OS/performance/accessibility/upgrade matrix under [#147](https://github.com/dalbrecht/dust3d-swiftui/issues/147). |

The public Apple Sources do not establish the planned skeletal evaluation,
animation/audio playback or complete export parity. Stored-intent controls are distinct from
those capabilities; an open issue series is not implementation evidence. The
node-ID fix in #251 closes #250, while the separate staged OBJ-status accessibility
investigation in #235 remains open. No milestone
above is accepted solely because its controls or a passing test suite exist.
Earlier verification files retain historical counts and scope; they are not
current whole-app coverage claims.

Explicit accepted-state recovery copies (#248) are prepared locally under
[ADR 0093](adr/0093-bounded-editor-recovery-copies.md), with pure admission and
ordinary temporary-file tests. They preserve originals/history and require a
matching request receipt. Native notification delivery remains unverified and
cannot retrofit the protected older QA process.

## Next delivery priorities

Per-document preview scheduling (#271) is merged through #274, with five pure queue
and seven fake-backend tests passing. The pure queue has 100% measured line,
region and function coverage; the focused service profile covers 184/198 lines.
Full preview-stage local validation passed: 45 support and 1,016 XCTest cases,
coverage, Qt-free linkage and bundle rebuilds. Queue line coverage is 28/28;
service line coverage is 194/198 in the full suite. Those historical results do
not establish native acceptance. Follow-up #276 tracks history-owned sources.
The separate reviewed
dependency upgrade #273 removed the automatic stitching debug SVG writer; its
full local gate and completed clean review/all CI passed. All feature quarantines
remain. See
[ADR 0114](adr/0114-per-document-preview-scheduling.md).

1. Finish the current public review gate and publish ready local stages serially.
   Preserve recoverable source/bundles and use the single shared compiler root.
2. Complete ordinary controlled M2/M3 acceptance before claiming those milestones:
   prioritize unsupported linked-profile replacements, further topology combinations and native-created Qt
   round trips. Do not repeat already-proven cases merely to grow counts.
3. Continue material adoption and safe domain foundations for rig/animation/export
   with explicit capability/error behavior. Saved experimental checkpoints require
   fresh source audit/builds; never run stale binaries or reopen quarantined paths.
4. Integrate reviewed core/worker stages only through explicit dependency and
   application PRs with the required acceptance. Runtime metadata is not a sandbox,
   and local helper tests do not establish complete app containment.
5. Close release gates with actual evidence. No feature percentage or calendar
   completion estimate is justified by this partial acceptance snapshot.

Preserve core [#67](https://github.com/dalbrecht/dust3d-core/issues/67)/
[#69](https://github.com/dalbrecht/dust3d-core/issues/69),
[#83](https://github.com/dalbrecht/dust3d-core/issues/83),
[#84](https://github.com/dalbrecht/dust3d-core/issues/84),
[#95](https://github.com/dalbrecht/dust3d-core/issues/95) and Apple
[#199](https://github.com/dalbrecht/dust3d-swiftui/issues/199) quarantines.
Core containment work remains tracked by
[#123](https://github.com/dalbrecht/dust3d-core/issues/123).
No crash, allocation-failure, signal-delivery, broken-pipe or resource-exhaustion
probes, production pin changes or human button requests are introduced by this audit.
