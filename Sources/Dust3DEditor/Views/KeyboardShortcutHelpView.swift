import SwiftUI

/// Native bindings only. Keep focus restrictions alongside the corresponding command.
enum KeyboardShortcutHelp {
    struct Entry: Equatable, Identifiable {
        let action: String
        let keys: String
        let scope: String
        var id: String { action }
        var spokenKeys: String {
            keys.split(separator: "/").map(KeyboardShortcutHelp.spokenKey).joined(separator: " or ")
        }
    }

    private static let keyNames: [Character: String] = [
        "⌘": "Command", "⌥": "Option", "⌃": "Control", "⇧": "Shift",
        "←": "Left Arrow", "→": "Right Arrow", "↑": "Up Arrow", "↓": "Down Arrow",
        "-": "Minus", "=": "Equals", ",": "Comma", ".": "Period",
        "[": "Left Bracket", "]": "Right Bracket",
    ]

    private static func spokenKey(_ key: Substring) -> String {
        key.map { character in
            keyNames[character].map { " \($0) " } ?? String(character)
        }.joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static let entries: [Entry] = [
        .init(action: "Undo / Redo", keys: "⌘Z / ⇧⌘Z", scope: "Focused text editor or document history"),
        .init(action: "Cut / Copy / Paste", keys: "⌘X / ⌘C / ⌘V", scope: "Focused text or editable nodes"),
        .init(action: "Select All", keys: "⌘A", scope: "Focused text or graph; unavailable in animation controls"),
        .init(action: "Select All Nodes", keys: "⇧⌘A", scope: "Active document"),
        .init(
            action: "Toggle Add / Return to Selection", keys: "A / S",
            scope: "Focused canvas or node, outside Move Origin and bone edge selection"),
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
                "Focused canvas, node or origin marker. Nudges the stored origin in Move Origin mode; otherwise the editable selection. No active drag. Choose Focus Canvas from the Canvas menu."
        ),
        .init(
            action: "Decrease / Increase Selection Spacing", keys: "[ / ]",
            scope: "Focused canvas, node or origin marker, with editable selection and no active drag"),
        .init(action: "Lock X / Y / Z / Radius", keys: "⌥⌘X / ⌥⌘Y / ⌥⌘Z / ⌥⌘R", scope: "Active document"),
        .init(action: "Show / Hide Sidebar", keys: "⌃⌘S", scope: "Focused editor window"),
        .init(action: "Show / Hide Inspector", keys: "⌃⌘I", scope: "Focused editor window"),
        .init(
            action: "Show Animations Inspector", keys: "⌥⌘A",
            scope:
                "Focused editor window with an accepted document and no open sheet. Choose Show Animations Inspector from the Window menu."
        ),
        .init(
            action: "Switch Editing Profile", keys: "E",
            scope: "Focused Side by Side canvas or node with a graph selection and no active drag"),
        .init(
            action: "Select Hovered Item’s Component", keys: "F",
            scope: "Focused canvas or node with a hovered graph item and no active drag"),
        .init(
            action: "Browse Selected Component Group", keys: "⌘↓",
            scope: "Focused component sidebar with one visible group selected"),
        .init(
            action: "Go to Enclosing Component Group", keys: "⌘↑",
            scope: "Focused component sidebar while browsing a group"),
        .init(action: "Cancel Canvas Input", keys: "Escape", scope: "Active node creation, node drag or origin drag"),
        .init(
            action: "Cancel Geometry Export", keys: "Escape",
            scope:
                "Cancellable export in the active document, outside text and animation controls, with no modal dialog and no active canvas input"
        ),
        .init(action: "Next Replay Step", keys: "⌥→", scope: "Replay Steps window, when a next step is available"),
        .init(
            action: "Assign Selected Edges to Bone", keys: "⌘Return",
            scope: "Active editor window with a chosen template bone and editable edge selection"),
        .init(
            action: "Commit Animation Draft", keys: "⌘Return",
            scope: "Animation authoring controls, when the draft is valid"),
        .init(
            action: "Edit Owning Component Properties", keys: "Space",
            scope: "Focused canvas with selected or hovered graph owners"),
    ]

    static func matching(_ query: String, in entries: [Entry] = entries) -> [Entry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        let exactKeys = entries.filter { entry in
            entry.keys.split(separator: "/").contains {
                $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(query) == .orderedSame
                    || spokenKey($0).caseInsensitiveCompare(query) == .orderedSame
            }
        }
        if !exactKeys.isEmpty { return exactKeys }
        return entries.filter {
            [$0.action, $0.keys, $0.spokenKeys, $0.scope].contains { $0.localizedCaseInsensitiveContains(query) }
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(entry.action)
                    .accessibilityValue("\(entry.spokenKeys). \(entry.scope)")
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
