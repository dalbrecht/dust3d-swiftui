# ADR 0149: Batch component reparenting

Status: Accepted

Qt's grid drop sorts selected sibling rows in display order before moving them into a group. Breadcrumb drops append in drag payload order and skip rows already under the destination. Each accepted drop saves one history snapshot. The existing native Move to Parent chooser is now shared by single and multiple selections. It offers the document root and supported unlinked groups.

The batch validates exact source and destination identities before mutation and rejects self or descendant destinations atomically. Complete selected subtrees append in document preorder. Selected descendants travel with their selected ancestors, and existing direct children stay in place. The original singleton domain command retains its behavior.

The transaction preserves inherited XML language, space, and base where the destination context can represent them. It uses bounded lexical namespace frames to hoist changed bindings and rejects a newly inherited named binding when XML 1.0 cannot represent its prior absence. A typed refusal leaves the archive untouched. The chooser captures document, selection, and constraint epochs so returning to a prior selection cannot revive a stale action. One Undo restores the original archive.

## Verification

The focused run passed 34 document, actor, and stubbed Store tests. The approved single native test on core `48b0ce2d6d61cf58731bb0c3e14ef5965a686d68` matched the independently authored edited archive before preview and compared oriented triangle multiplicities through the 48-to-16 move, Undo, redo, and reopen. Graph, camera, and selection assertions passed. Physical chooser interaction and native drag-and-drop remain outside this evidence.

The retained host has SHA-256 `cc6b61ff61450c57d5f1a73ea19e764e87f28469c44341e359e5b9ec1d92108a` and UUID `47FA0D67-7DBA-3237-9386-9F81BBED142E`. Its tested source digest before this ADR was `0d771c1c518b6d1c7fb259b260b0647e31f8e49fa81025e284428d29fc9e1fed`. The native log SHA-256 is `9113892ed176d1e9d83b4f8e2a3e2a9be1e51de5c338d81c046404f6d40458a4`.
