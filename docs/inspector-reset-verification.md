# Inspector numeric Reset regression

Native QA reproduced #29 on the previous editor: select Node 2, focus X, Command-A then Delete, and click Reset. The field could remain visually blank because its numeric binding still held 0.5 and assigning the same value did not replace the formatter’s invalid text buffer.

The fix changes the numeric Form identity on explicit Reset or a selected-node value reset. It recreates only that field-editing subtree, retaining native locale-aware number formatting and leaving session/document/selection/history untouched.

Full `make ci` passes 165 tests, both app builds, formatting, unchanged coverage gates and Qt-free linkage. Native regression verification used the isolated QA app and an asset-bearing three-node fixture:

- Empty X draft followed by Reset restored 0.5 visibly and in accessibility field values.
- Radius text `oops` followed by Reset restored 0.16.
- Invalid X text followed by switching from Node 2 to Node 3 restored X 0.5, Y 0.75, Z 1 and Radius 0.12, including the coordinate shared by both nodes.
- The graph stayed at three nodes/80 triangles, the document stayed unedited, and Undo/Redo stayed disabled. Visually inspected the restored inspector and quit the QA app without saving.

The SwiftPM Dust3DEditorTests integration target hosts the real NodeInspector in an offscreen AppKit window. It uses the native NSTextView field editor to enter empty and nonnumeric drafts, invokes the same InspectorNodeDraft.reset action as the Reset button, and asserts the actual displayed field text plus unchanged archive/history. It inspects public NSTextField/NSView APIs, without private class names, accessibility permissions, screenshots or synthesized system input. The native button wiring is also exercised by the manual QA above.

Mutation verification temporarily removed the Form reset identity: the integration test failed because empty and `oops` text remained displayed. Restoring the fix made it pass. This proves the test detects recurrence without asserting the identity token itself. The new target runs in the standard `make ci` suite and requires a macOS WindowServer session; a missing environment fails rather than silently skipping coverage. No new third-party dependency, archive or C++ change is involved. VoiceOver and oldest-supported-macOS behavior are not certified.
