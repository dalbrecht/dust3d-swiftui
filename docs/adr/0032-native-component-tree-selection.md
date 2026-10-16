# ADR 0032: Native component tree selection

Status: Accepted; see native evidence and remaining acceptance limits

## Decision

Cache a pure `ComponentTree` presentation beside editable graph contents, computed when a document opens or its bytes change on the editing actor. Rows retain XML preorder, component identity, depth and source names. Unnamed groups/components get deterministic display labels without writing those labels into the archive. Linear filtering hides descendants of collapsed groups; view-local collapse state resets on document replacement and never enters save/undo data.

Component selection is exclusive with node/edge/part selection and belongs to one editor session. Selecting a component does not dirty the document, allocate history or imply a geometry selection. Add Node is disabled for this inspector selection; New Part remains an explicit command. Linked-part inspection switches to the existing part controls. Deleted component selections are pruned on publication and not resurrected by Undo.

The sidebar uses native list rows, inline disclosure buttons and an explicit native tree-actions menu for accessible collapse/expand commands. Its indentation is capped after six levels for usable narrow rows; parent identity and exact order remain in the model/inspector. Part and edge panes use smaller scrollable maxima to leave room for the component tree. The inspector edits component names independently of legacy part names, preserves name drafts until explicit Apply/Return, and refreshes after identity changes or undo/redo.

Unsupported hierarchies degrade only the tree presentation. The original interpretation error is shown beside the preservation statement; graph editing and exact archive saving remain available. No parser is run in view rendering and no failed interpretation silently repairs component data.

## Remaining scope

Grouping/reparenting/reordering and component modifier/ancestor lock semantics remain separate stages in #62. This tree does not claim geometry-editing support for every hierarchy or complete Qt parity. See [verification](../component-tree-verification.md) for native history/rendered checks and remaining keyboard/VoiceOver limits. No dependency, core pin, CI or lockfile changes.
