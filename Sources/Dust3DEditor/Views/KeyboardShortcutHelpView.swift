import SwiftUI

/// Native bindings only. Keep focus restrictions alongside the corresponding command.
enum KeyboardShortcutHelp {
    struct Entry: Equatable, Identifiable {
        let action: String
        let keys: String
        let scope: String
        var id: String { action }
    }

    static let entries: [Entry] = [
        .init(action: "Undo / Redo", keys: "⌘Z / ⇧⌘Z", scope: "Focused text editor or document history"),
        .init(action: "Cut / Copy / Paste", keys: "⌘X / ⌘C / ⌘V", scope: "Focused text or editable nodes"),
        .init(action: "Select All", keys: "⌘A", scope: "Focused text or graph; unavailable in animation controls"),
        .init(action: "Select All Nodes", keys: "⇧⌘A", scope: "Active document"),
        .init(
            action: "Remove Graph Picks", keys: "⌥⌘ click / drag",
            scope: "Canvas nodes, edges or marquee; removes hits while preserving the other picks"),
        .init(action: "Export OBJ Geometry", keys: "⇧⌘E", scope: "Active document with available export geometry"),
        .init(
            action: "Decrease / Increase Radius", keys: "- / =",
            scope: "Focused canvas or node, with an editable graph selection and no active drag"),
        .init(
            action: "Rotate Selection −1° / +1°", keys: ", / .",
            scope: "Editable graph selection, outside text and animation controls"),
        .init(
            action: "Delete Graph Selection", keys: "Delete",
            scope: "Graph selection, outside text, animation and component sidebar controls"),
        .init(
            action: "Delete in Canvas", keys: "Forward Delete / ⌃D",
            scope: "Focused canvas or graph handle with an editable selection and no active drag"),
        .init(
            action: "Nudge Selection or Origin", keys: "← / → / ↑ / ↓",
            scope:
                "Focused canvas, node or origin marker. Nudges the stored origin in Move Origin mode; otherwise the editable selection. No active drag"
        ),
        .init(
            action: "Decrease / Increase Selection Spacing", keys: "[ / ]",
            scope: "Focused canvas, node or origin marker, with editable selection and no active drag"),
        .init(action: "Lock X / Y / Z / Radius", keys: "⌥⌘X / ⌥⌘Y / ⌥⌘Z / ⌥⌘R", scope: "Active document"),
        .init(action: "Show / Hide Inspector", keys: "⌃⌘I", scope: "Focused editor window"),
        .init(action: "Show Animations Inspector", keys: "⌥⌘A", scope: "Editor window"),
        .init(action: "Cancel Canvas Input", keys: "Escape", scope: "Active node creation, node drag or origin drag"),
        .init(action: "Next Replay Step", keys: "⌥→", scope: "Replay Steps window, when a next step is available"),
        .init(
            action: "Assign Selected Edges to Bone", keys: "⌘Return",
            scope: "Active editor window with a chosen template bone and editable edge selection"),
        .init(
            action: "Commit Animation Draft", keys: "⌘Return",
            scope: "Animation authoring controls, when the draft is valid"),
    ]

    static func matching(_ query: String, in entries: [Entry] = entries) -> [Entry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            [$0.action, $0.keys, $0.scope].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

struct KeyboardShortcutHelpView: View {
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts").font(.title2).accessibilityAddTraits(.isHeader)
            Text(
                "Commands apply to the active window and selection. Text fields keep their native editing keys. Menu items show whether a command is available."
            )
            .foregroundStyle(.secondary)
            TextField("Search actions, keys, or focus", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search keyboard shortcuts")
            List {
                ForEach(KeyboardShortcutHelp.matching(query)) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(entry.action, value: entry.keys)
                        Text(entry.scope).font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
            .overlay {
                if KeyboardShortcutHelp.matching(query).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            Text("⌘ Command · ⌥ Option · ⌃ Control · ⇧ Shift. Follow the focus scope shown for each command.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 580, minHeight: 420)
    }
}
