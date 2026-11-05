# ADR 0148: Batch component Ungroup

Status: Accepted

Qt offers Ungroup for component rows with children and saves one history snapshot after acting on all selected rows. The native component tree also permits selecting ancestors and descendants together. Ungroup removes every explicitly selected eligible wrapper and promotes its contents in source order. A selected leaf is left alone. The same transaction serves one or more rows in the sidebar menu, row context menu, and inspector. The legacy single-component document command retains its original admission rules.

Ungroup discards the wrapper's settings, links, and custom attributes. It preserves surviving children, authored graph, assets, and incoming soft references. The transaction validates raw UTF-8 identities before deduplication and constructs each affected parent's final child sequence once. It checks inherited XML language, space, and the full base chain before moving content. Only a strictly parsed absolute base can reset that chain. Persistent namespace frames preserve element bindings within explicit work and output budgets. Non-whitespace text and CDATA cannot carry declarations, so a move that would change their namespace context fails atomically. This policy preserves declared XML context where established. Opaque application semantics can depend on the removed wrapper itself.

The action captures the document and selection context at admission. Stale actions cannot retarget a different selection or window. One Undo restores the original document and graph editing state. Selection pruning follows the existing history policy.

## Verification

The focused suite passed 34 document, model, and stubbed editor tests. The batch document implementation covered 230 of 241 lines and 146 of 163 regions. Hosted renders cover the action's single and multiple selection labels. Physical desktop menu delivery remains open.

One exact native test on core `48b0ce2d6d61cf58731bb0c3e14ef5965a686d68` verified that the ordinary wrapped source matches its independent 16-triangle anchor and that Ungroup, redo, and reopen match the independently authored 48-triangle flat archive by oriented triangle multiplicity. The test also verifies exact archive Undo and graph and camera preservation. The initial document-only byte comparison exposed a 17-byte encoding declaration in the independent header oracle. The corrected builder produced bytes identical to the retained document output before native execution.

The retained native host has SHA-256 `80469d4883056c10a01db131be2f74723c7ba9b4ff818a6cdb72d8d07d62c162` and UUID `DEAFE117-AD7A-3797-9DA3-0B02FAEE4897`. Its tested source digest was `3943ea7929d83b5722d29cd94f39de065de5851bce19420b435ebb46bec32b3f` before this ADR was added. The one-method log SHA-256 is `009cc104f41d668c08bb1035b87e78ac77404577cb191239ce902eeaaa5b488e`.
