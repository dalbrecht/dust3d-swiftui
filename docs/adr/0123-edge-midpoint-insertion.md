# ADR 0123: Insert a midpoint in a selected edge

Status: accepted; local native release gates passed on 2026-11-01.

## Context

Qt's `Document::breakEdge` subdivides a directed edge at the average endpoint position and radius. The native editor previously exposed reversal and deletion but no subdivision command. This is a bounded graph-editing parity step that uses the existing reviewed core dependency.

## Decision

Expose an atomic document command with explicit fresh node and second-edge identities. Retain the original edge identity and direction as the first segment. The second segment connects the midpoint to the original destination and copies the known edge name and bone binding. Preserve opaque metadata on the original edge and all unrelated archive content. Do not infer how unknown edge fields should propagate.

Validate identity collisions, ownership, editable endpoints, finite bounded geometry and graph limits before publication. Apply through existing immutable document history so failure is atomic and Undo restores the original archive in one step. The editor retains selection of the original edge. Session code allocates new UUIDs; the document layer is deterministic.

Expose the operation in the edge inspector and Canvas menu using one store action and availability rule. Do not invent a keyboard shortcut. Menu access follows [Apple's menu guidance](https://developer.apple.com/design/human-interface-guidelines/menus); keyboard and VoiceOver acceptance require native interaction evidence beyond source tests.

## Verification

Document contracts cover topology, numeric geometry, known/opaque metadata, identities, ownership, limits, assets, save/reopen and history. Model and store contracts cover selection, rejection, routing and busy/readonly states. Preview and inspector rendering use the unchanged production core pin. Run the full native gates before tagging a new usable checkpoint. Offscreen rendering does not establish physical keyboard or VoiceOver acceptance.

Local validation: 60 build-support and 1,153 XCTest tests passed, configured coverage gates and Qt-free linkage passed, and isolated bundle rebuild/signature verification passed. Eight focused document contracts are included. Six inspector states were rendered. These results do not establish physical keyboard or VoiceOver acceptance.
