# Native editor delivery and acceptance status

Snapshot: October 23, 2026. The full scope remains
[editor-port-plan.md](editor-port-plan.md), including M0–M8. This snapshot separates
implemented stages, local work and missing acceptance; it is not a parity signoff.

## Public and local baselines

- Apple public master: `2be446e078a86504ae8f1a5aa2b48336108f1322` (reviewed PR #251).
  Crop adjustment (#249) and the native node-ID accessibility/copy fix (#251) are
  merged. Historical modifier/clipboard QA used clean implementation `2011b362`;
  later documentation and test commits do not retag that captured runtime.
- Core public master: `69b428bd70e8b2f582502c83661f92a6df0a70a7` (reviewed PR #125).
  Transport #122, queue #124 and pure lifetime policy #125 merged after completed
  review and all green CI. Supervision/resource stages through saved `4c998e86`
  remain unpublished. The pure policy does not itself enforce process lifetime.
- Apple continues to pin core `41af7d4c1b67dd037e02858e3ef0fdb96a84aebb`.
  Local core contracts and helper tests are not evidence of Apple adoption.
- Every public PR still requires its full local gate, completed exact-head
  automated review, addressed feedback and all green CI before serial merging.
  A stale running summary is not proof of worker liveness or permission to retry.

## Milestone evidence and gaps

| Milestone | Evidence established | Acceptance still open |
| --- | --- | --- |
| M0 — Viewer/baseline | Separate viewer and native editor products; shared standards and maintained MIT downstream. Selected ordinary Qt CPU comparisons are recorded in core issue #35. | Complete action/serialization inventory and broad licensed differential corpus; selected CPU cases are not full Qt GUI/export parity. |
| M1 — Document/persistence | Lossless document/undo foundation, bounded archives, typed errors and save snapshot guard: [foundation](editor-foundation-verification.md), [native save](native-save-snapshot-verification.md). | Qt reopen of native-created corpus, broader recovery/close-cancel and physical filesystem acceptance. Simulated write failures do not prove all OS failures. |
| M2 — Canvas/editor | Node/edge creation/deletion/history, selection/transforms, front/side editing, references, separate windows; crop adjustment is merged in #249. Controlled two-window/drag evidence is tracked in [#245](https://github.com/dalbrecht/dust3d-swiftui/issues/245). | Native-created capsule and multi-part sword reopened in Qt; held-gesture Escape, responsiveness/stale-result scenarios, keyboard/VoiceOver/older macOS. |
| M3 — Modeling | Hierarchy/modifier document/controller suites and scoped native checks, now including [controlled thickness/unified and intersecting hard-join history/reopen](controlled-native-modifier-acceptance.md). | Broader linked topology interactions/replacements, remaining families and Qt comparisons. Hollow-thickness consumer gap remains [#96](https://github.com/dalbrecht/dust3d-swiftui/issues/96); [#120](https://github.com/dalbrecht/dust3d-swiftui/issues/120) stays open. |
| M4 — Materials/imports | Existing material/import/bake/render stages have [editor evidence](imported-material-editor-verification.md) and [file-preview evidence](mixed-file-preview-verification.md). | Mixed source mip adoption [#172–180](https://github.com/dalbrecht/dust3d-swiftui/issues/172), full alpha/PBR/UV/export parity and malformed-asset containment. Historical render evidence does not enable the quarantined experimental catalog. [#143](https://github.com/dalbrecht/dust3d-swiftui/issues/143) remains open. |
| M5 — Rigging | Local stored-parameter/inspector stage #246 and bone-assignment stage #247 have document/controller tests and scoped render evidence. They are saved separately and not yet public adoption or native rig evaluation. | Rig/pose ownership, skeleton/hierarchy/weights, IK and native save/keyboard acceptance under [#144](https://github.com/dalbrecht/dust3d-swiftui/issues/144) and its staged issues. Preserve Apple #199 quarantine. |
| M6 — Animation/audio | Existing archive fields can be retained; no full native evaluation/playback/audio acceptance exists. | Catalog/commands, bounded pose/audio copies, time-based playback, synchronization and WAV workflows under [#145](https://github.com/dalbrecht/dust3d-swiftui/issues/145). Preserve core #95 quarantine. |
| M7 — Export/batch | Portable development work and staged issues exist; document Save is not export parity. | Owned OBJ/GLB/FBX/WAV outputs, atomic publication, current-revision admission and independent re-import/batch acceptance under [#146](https://github.com/dalbrecht/dust3d-swiftui/issues/146). |
| M8 — Release/hardening | Measured Swift suites, explicit Qt-free builds, file-preview integration stages and local core mitigation contracts. | Strong memory/descendant/filesystem/network/parent-death containment, active lifecycle evidence, trusted packaging/signing/notarization, hardware/OS/performance/accessibility/upgrade matrix under [#147](https://github.com/dalbrecht/dust3d-swiftui/issues/147). |

The public Apple Sources do not expose the planned skeletal evaluation,
animation/audio/export workflows. Local stored-intent controls are distinct from
those capabilities; an open issue series is not implementation evidence. The
node-ID fix in #251 closes #250, while the separate staged OBJ-status accessibility
investigation in #235 remains open. No milestone
above is accepted solely because its controls or a passing test suite exist.
Earlier verification files retain historical counts and scope; they are not
current whole-app coverage claims.

## Next delivery priorities

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
