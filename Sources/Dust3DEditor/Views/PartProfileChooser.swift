import Dust3DDocument
import SwiftUI

struct PartProfileChooser: View {
    let store: EditorStore
    let part: DocumentPart
    @State private var query = ""

    private var candidates: [DocumentPart] {
        (store.snapshot?.parts ?? []).filter {
            $0.id != part.id
                && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                    || $0.id.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search profile parts", text: $query)
                .accessibilityIdentifier("part-profile-search")
                .focusedValue(\.editorTextEditing, true)
            if candidates.isEmpty {
                Text("No matching other parts.").font(.caption)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(candidates) { candidate in
                            Button {
                                store.setPartCutFace(part.id, selection: .linkedPart(candidate.id))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title).lineLimit(1)
                                    Text(candidate.id).font(.caption2).lineLimit(1)
                                }
                            }
                            .help(candidate.title + "\n" + candidate.id)
                            .accessibilityLabel("Link profile \(candidate.title), \(candidate.id)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
                .accessibilityLabel("Profile parts")
            }
            Text("Choose a part to link immediately. Cyclic dependencies are rejected without changing the document.")
                .font(.caption).foregroundStyle(.primary)
        }
        .onChange(of: part.id) { _, _ in query = "" }
        .onChange(of: store.snapshot?.documentIdentity) { _, _ in query = "" }
    }
}
