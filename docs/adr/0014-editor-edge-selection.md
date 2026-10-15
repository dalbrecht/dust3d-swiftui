# ADR 0014: Transient edge selection and canvas picking

Accepted 2026-10-15. Implements edge picking from M2, tracked in #27.

Keep a single selectedEdgeID in EditorState, mutually exclusive with the node selection set. Selection changes never dirty documents or create history. Invalid edge IDs reject atomically. Reversal retains the selected identity; deletion prunes it, and Undo restores the archive without reviving transient selection. Selecting nodes, selecting all nodes, or clearing selection clears the edge selection. Add Node is disabled for an edge selection; explicit New Part remains available.

Canvas picking finds the nearest visible projected segment within eight screen points, with deterministic document-order ties. Ignore missing/hidden endpoints and segments that collapse in the chosen plane. Node handles remain above the background picker so endpoint clicks continue selecting nodes. Marquee dragging remains node selection, even when crossing an edge. An accessible edge sidebar provides a keyboard/native-accessibility alternative, including collapsed projections and hidden/read-only edges for inspection.

Show directed endpoints, identity, Select Endpoints, Reverse Edge and Delete Edge in the inspector. Both endpoints must be editable for mutation. Selected-edge deletion routes through EditorSession's existing normalized deletion transaction so disconnected pieces receive distinct parts and Undo restores exact archive bytes. No new archive format, C++ engine change or dependency is introduced. Edge creation remains endpoint connection; edge subdivision and simultaneous edge multiselection are separate interactions.
