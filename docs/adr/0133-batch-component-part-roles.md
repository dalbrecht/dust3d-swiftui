# ADR 0133: Batch component part roles and stitching groups

Status: accepted for local delivery; physical input and VoiceOver acceptance outstanding.

## Context

Qt exposes Part Role on directly selected part-linked component rows (`part_manage_widget.cc:354–422`, `component_preview_grid_widget.cc:138–173`). Model, CutFace, StitchingLine and StitchingLoop have supported native geometry. ImportedModel requires a separate embedded-model pipeline and remains a known gap. Single-part inspector editing did not supply the multi-row workflow or the automatic shared stitching group.

## Decision

Resolve only explicitly selected part-linked rows, in document order. Selected groups contribute no descendant expansion. Resolve each actual part to exactly one component owner and reject missing/ambiguous owners before any mutation. Preserve the Qt setter policy: hidden, disabled and locked parts may change role; their flags and opaque attributes remain unchanged. Axis/radius locks do not change the metadata meaning.

Model and CutFace allow cross-parent selections. Single-part role assignment performs no hierarchy mutation, including under opaque linked parents. Multiple stitching parts must share a parent. Reuse a common non-root unlinked group, including its unselected siblings and existing settings; reject cross-parent or linked-parent grouping atomically. Root stitching siblings receive a fresh session-owned UUID group at the first selected row position, retaining document child order. Matching source roles do not suppress required root grouping. Matching roles in a reused group preserve exact archive/history/preview inputs but still select and reveal that group.

One bulk document command uses one parsed hierarchy context and part index, preflights ownership and grouping, and serializes the changed model once. Existing archive validation, XML depth/byte limits and the 10,000-component ceiling remain authoritative. Constant additional archive-validation passes retain O(N+K) work; no per-selected-part XML parse/serialize loop is used. Fresh group creation consumes one component slot; reuse consumes none. Roles/grouping retain existing geometry and material preview invalidation semantics.

Capture document identity/revision, component-selection and constraint epochs before queuing the action. Reject selection/lock away-and-back, Undo, replacement and cross-window targets. Stage state on a copy and check cooperative cancellation before actor publication. Shared accessible sidebar and inspector menus use captured actions; a disabled captured action cannot acquire a later selection. Reveal uses a distinct component hint epoch and the real sidebar expansion/scroll path. One command produces one undo entry; no-op group reveal produces none.

## Verification

Test-first evidence covers role/group planning, real Store dispatch, source-order placement, reuse with unselected children, exact no-op bytes, invalid owners/identities/parents, all four roles, part flags, component/history limits and one-step Undo/Redo/reopen. Bounded ordinary maintained three-by-three line and two-by-four loop profiles are converted from root Model parts by the actual action, then compared against independently serialized stitching fixtures. Geometry comparison retains every triangle occurrence and winding; no coincident-vertex welding is used.

Hosted light/dark controls and an actual offscreen native sidebar verify group reveal. Physical input and VoiceOver acceptance remain outstanding. This work changes no production core pin, dependency, quarantine, remote publication or protected QA process.

The complete pinned local gate passed 60 BuildSupport tests and 1,347 XCTest tests, configured coverage (including 894/894 EditorState lines), Qt-free linkage and isolated bundle rebuild/signature checks. This evidence does not establish full Qt parity or HIG acceptance.
